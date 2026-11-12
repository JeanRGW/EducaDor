"""Opt-in actual AWS CLI test against a loopback-only S3 protocol fixture; no cloud access."""
import contextlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from unittest.mock import patch

import publish


class S3Fixture(BaseHTTPRequestHandler):
    objects = {}
    paths = []
    fail_list = False

    def log_message(self, *_):
        pass

    def do_PUT(self):
        self.__class__.paths.append(self.path)
        self.__class__.objects[urlsplit(self.path).path] = self.rfile.read(int(self.headers['Content-Length']))
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        self.__class__.paths.append(self.path)
        parsed = urlsplit(self.path)
        query = parse_qs(parsed.query)
        if query.get('list-type') == ['2']:
            if self.fail_list:
                self.send_error(500)
                return
            page = query.get('continuation-token', [''])[0]
            key, token = ('first', '<NextContinuationToken>next</NextContinuationToken>') if not page else ('second', '')
            truncated = 'false' if page else 'true'
            body = (f'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
                    f'<Name>educador-backups</Name><IsTruncated>{truncated}</IsTruncated>'
                    f'<Contents><Key>{key}</Key><Size>1</Size><LastModified>2026-01-01T00:00:00.000Z</LastModified></Contents>'
                    f'{token}</ListBucketResult>').encode()
        elif parsed.path in self.objects:
            body = self.objects[parsed.path]
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@unittest.skipUnless(os.environ.get('BACKUP_CLI_TEST') == '1', 'set BACKUP_CLI_TEST=1 with pinned awscli installed')
class CliIntegrationTest(unittest.TestCase):
    def test_cli_path_pagination_and_errors(self):
        self.assertIsNotNone(shutil.which('aws'))
        version = subprocess.check_output(['aws', '--version'], stderr=subprocess.STDOUT).decode()
        self.assertIn('aws-cli/1.36.40 ', version)
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
            stack.enter_context(patch.dict(os.environ, {
                'BACKUP_S3_ENDPOINT': f'http://127.0.0.1:{server.server_port}/storage/v1/s3',
                'AWS_CONFIG_FILE': str(config), 'AWS_SHARED_CREDENTIALS_FILE': str(credentials),
                'AWS_ACCESS_KEY_ID': 'test', 'AWS_SECRET_ACCESS_KEY': 'test', 'AWS_DEFAULT_REGION': 'sa-east-1',
                'AWS_EC2_METADATA_DISABLED': 'true', 'AWS_MAX_ATTEMPTS': '1', 'AWS_RETRY_MODE': 'standard',
                'NO_PROXY': '127.0.0.1',
            }))
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
