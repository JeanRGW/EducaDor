"""Opt-in actual AWS CLI test against a loopback-only S3 protocol fixture; no cloud access."""
import contextlib
import http.client
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch

import publish

# Variables a developer machine or CI image may preset that would redirect the CLI
# away from the loopback fixture or change credential/config lookup.
HOSTILE = ('AWS_PROFILE', 'AWS_DEFAULT_PROFILE', 'AWS_SESSION_TOKEN', 'AWS_SECURITY_TOKEN',
           'AWS_CA_BUNDLE', 'AWS_CONFIG_FILE', 'AWS_SHARED_CREDENTIALS_FILE', 'AWS_ENDPOINT_URL',
           'AWS_PAGER', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy',
           'all_proxy')
FIXTURE_ENV = {
    'AWS_ACCESS_KEY_ID': 'test', 'AWS_SECRET_ACCESS_KEY': 'test', 'AWS_DEFAULT_REGION': 'sa-east-1',
    'AWS_EC2_METADATA_DISABLED': 'true', 'AWS_MAX_ATTEMPTS': '1', 'AWS_RETRY_MODE': 'standard',
    'AWS_PAGER': '', 'NO_PROXY': '127.0.0.1', 'no_proxy': '127.0.0.1',
}


class S3Fixture(BaseHTTPRequestHandler):
    objects = {}
    paths = []
    fail_list = False
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def respond(self, status, body):
        # A single explicit close keeps the loopback connection deterministic.
        self.send_response(status)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self):
        self.__class__.paths.append(self.path)
        self.__class__.objects[urlsplit(self.path).path] = self.rfile.read(int(self.headers['Content-Length']))
        self.respond(200, b'')

    def do_GET(self):
        self.__class__.paths.append(self.path)
        parsed = urlsplit(self.path)
        query = parse_qs(parsed.query)
        if query.get('list-type') == ['2']:
            if self.fail_list:
                self.respond(500, b'injected listing failure')
                return
            page = query.get('continuation-token', [''])[0]
            key, token = ('first', '<NextContinuationToken>next</NextContinuationToken>') if not page else ('second', '')
            truncated = 'false' if page else 'true'
            body = (f'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
                    f'<Name>educador-backups</Name><IsTruncated>{truncated}</IsTruncated>'
                    f'<Contents><Key>{key}</Key><Size>1</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified></Contents>'
                    f'{token}</ListBucketResult>').encode()
            self.respond(200, body)
        elif parsed.path in self.objects:
            self.respond(200, self.objects[parsed.path])
        else:
            self.respond(404, b'missing')


def ready(port, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=1):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError('loopback fixture did not accept connections')


@unittest.skipUnless(os.environ.get('BACKUP_CLI_TEST') == '1', 'set BACKUP_CLI_TEST=1 with pinned awscli installed')
class CliIntegrationTest(unittest.TestCase):
    def test_cli_path_pagination_and_errors(self):
        self.assertIsNotNone(shutil.which('aws'))
        version = subprocess.check_output(['aws', '--version'], stderr=subprocess.STDOUT).decode()
        self.assertIn('aws-cli/1.36.40 ', version)
        # awscli 1.36.40 raises "badly formed help string" on Python 3.14's argparse.
        # Fail with an actionable message instead of an opaque CLI exit status.
        python = version.rsplit('Python/', 1)[-1].split()[0]
        self.assertLess(tuple(map(int, python.split('.')[:2])), (3, 14),
                        f'awscli 1.36.40 cannot run on Python {python}; use 3.12 or 3.13')
        S3Fixture.objects, S3Fixture.paths, S3Fixture.fail_list = {}, [], False
        with tempfile.TemporaryDirectory() as tmp, contextlib.ExitStack() as stack:
            root = Path(tmp)
            config = root / 'config'
            config.write_text('[default]\nregion = sa-east-1\ns3 =\n    addressing_style = path\n')
            credentials = root / 'credentials'
            credentials.write_text('')
            server = ThreadingHTTPServer(('127.0.0.1', 0), S3Fixture)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            stack.callback(server.server_close)
            stack.callback(thread.join)
            stack.callback(server.shutdown)
            ready(server.server_port)
            environment = {k: v for k, v in os.environ.items() if k not in HOSTILE}
            environment.update(FIXTURE_ENV)
            environment.update({
                'BACKUP_S3_ENDPOINT': f'http://127.0.0.1:{server.server_port}/storage/v1/s3',
                'AWS_CONFIG_FILE': str(config), 'AWS_SHARED_CREDENTIALS_FILE': str(credentials),
            })
            stack.enter_context(patch.dict(os.environ, environment, clear=True))
            source = root / 'source'
            source.write_bytes(b'test bytes')
            publish.put('database/v1/test', source)
            self.assertEqual(publish.get('database/v1/test', 10, root), b'test bytes')
            self.assertEqual(set(publish.inventory()), {'first', 'second'})
            self.assertGreaterEqual(sum('list-type=2' in p for p in S3Fixture.paths), 2)
            self.assertTrue(all(p.startswith('/storage/v1/s3/educador-backups') for p in S3Fixture.paths))
            S3Fixture.fail_list = True
            with self.assertRaises(subprocess.CalledProcessError):
                publish.inventory()
