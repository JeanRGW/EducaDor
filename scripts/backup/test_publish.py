import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import archive
import publish


class FakeS3:
    def __init__(self):
        self.objects = {}
        self.clock = 0
        self.corrupt = False
        self.fail_put = False
        self.deleted = []

    def __call__(self, command, **kwargs):
        args = command[command.index('s3api') + 1:]
        operation = args[0]
        def value(flag):
            return args[args.index(flag) + 1]
        if operation == 'list-objects-v2':
            data = {'Contents': [{'Key': k, 'Size': len(v[0]), 'LastModified': v[1]}
                                 for k, v in self.objects.items()]}
            output = json.dumps(data).encode()
        elif operation == 'put-object':
            if self.fail_put:
                raise subprocess.CalledProcessError(1, command)
            self.clock += 1
            self.objects[value('--key')] = (Path(value('--body')).read_bytes(), f'{self.clock:08d}')
            output = b'{}'
        elif operation == 'get-object':
            data = self.objects[value('--key')][0]
            if self.corrupt:
                data = bytes([data[0] ^ 1]) + data[1:]
            Path(args[-1]).write_bytes(data)
            output = b'{}'
        elif operation == 'delete-object':
            key = value('--key')
            self.deleted.append(key)
            del self.objects[key]
            output = b'{}'
        else:
            raise AssertionError(operation)
        return subprocess.CompletedProcess(command, 0, output)


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        part = b'encrypted data'
        (self.root / '0000.gpgpart').write_bytes(part)
        (self.root / 'manifest.json').write_text(json.dumps({'version': 1, 'parts': [
            {'name': '0000.gpgpart', 'size': len(part), 'sha256': archive.digest(part)}]}))
        self.s3 = FakeS3()
        self.env = patch.dict('os.environ', {'BACKUP_S3_ENDPOINT': 'https://test.storage.supabase.co/storage/v1/s3'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.runner = patch.object(publish.subprocess, 'run', side_effect=self.s3)
        self.runner.start()
        self.addCleanup(self.runner.stop)
        self.secret = b'x' * 32

    def publish(self, budget=100000, reserve=100):
        publish.publish(self.root, budget, reserve, self.secret)

    def test_retention_only_confirmed_and_unknown_preserved(self):
        self.s3.objects['database/v1/../evil'] = (b'x', '0')
        self.s3.objects['database/v1/' + 'a' * 32 + '/0000.gpgpart'] = (b'x', '0')
        for _ in range(4):
            self.publish()
        markers = [k for k in self.s3.objects if k.endswith('/complete.json')]
        self.assertEqual(len(markers), 3)
        self.assertEqual(len(self.s3.deleted), 3)
        self.assertIn('database/v1/../evil', self.s3.objects)
        self.assertIn('database/v1/' + 'a' * 32 + '/0000.gpgpart', self.s3.objects)

    def test_budget_and_upload_failure(self):
        with self.assertRaises(ValueError):
            self.publish(budget=100)
        self.assertFalse(self.s3.objects)
        self.s3.fail_put = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertFalse(self.s3.deleted)

    def test_readback_failure_never_marks_complete_or_prunes(self):
        self.s3.corrupt = True
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(any(k.endswith('/complete.json') for k in self.s3.objects))
        self.assertFalse(self.s3.deleted)

    def test_untrusted_completed_backup_is_not_pruned(self):
        self.publish()
        marker = next(k for k in self.s3.objects if k.endswith('/complete.json'))
        _, timestamp = self.s3.objects[marker]
        self.s3.objects[marker] = (b'{"version":1,"manifest_sha256":"' + b'0' * 64 +
                                   b'","hmac_sha256":"' + b'0' * 64 + b'"}', timestamp)
        for _ in range(4):
            self.publish()
        self.assertIn(marker, self.s3.objects)
        self.assertNotIn(marker, self.s3.deleted)

    def test_bad_manifest_name_and_untrusted_marker(self):
        manifest = json.loads((self.root / 'manifest.json').read_text())
        manifest['parts'][0]['name'] = '../secret'
        (self.root / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(self.s3.objects)


if __name__ == '__main__':
    unittest.main()
