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
        self.corrupt = False
        self.fail_put = False
        self.calls = []

    def __call__(self, command, **kwargs):
        args = command[command.index('s3api') + 1:]
        operation = args[0]
        self.calls.append((operation, args))
        def value(flag):
            return args[args.index(flag) + 1]
        if operation == 'list-objects-v2':
            data = {'Contents': [{'Key': k, 'Size': len(v)} for k, v in self.objects.items()]}
            output = json.dumps(data).encode()
        elif operation == 'put-object':
            if self.fail_put:
                raise subprocess.CalledProcessError(1, command)
            self.objects[value('--key')] = Path(value('--body')).read_bytes()
            output = b'{}'
        elif operation == 'delete-object':
            del self.objects[value('--key')]
            output = b'{}'
        elif operation == 'get-object':
            data = self.objects[value('--key')]
            if self.corrupt:
                data = bytes([data[0] ^ 1]) + data[1:]
            Path(args[-1]).write_bytes(data)
            output = b'{}'
        else:
            raise AssertionError(operation)
        kwargs['stdout'].write(output)
        return subprocess.CompletedProcess(command, 0, output)


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        part = b'encrypted data'
        (self.root / '0000.gpgpart').write_bytes(part)
        (self.root / 'manifest.json').write_text(json.dumps({'version': 2, 'parts': [
            {'name': '0000.gpgpart', 'size': len(part), 'sha256': archive.digest(part)}]}))
        (self.root / 'manifest.sig').write_bytes(b'signature')
        self.verify = patch.object(archive, 'verify_signature')
        self.verify.start()
        self.addCleanup(self.verify.stop)
        self.s3 = FakeS3()
        self.env = patch.dict('os.environ', {'BACKUP_S3_ENDPOINT': 'https://test.storage.supabase.co/storage/v1/s3'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.runner = patch.object(publish.subprocess, 'run', side_effect=self.s3)
        self.runner.start()
        self.addCleanup(self.runner.stop)
        self.secret = b'x' * 32

    def publish(self, budget=100000, reserve=100, egress=21_000_000, attestations=('true', 'true', 'true')):
        publish.publish(self.root, budget, reserve, egress, self.secret, attestations, 'A' * 40)

    def test_recurring_runs_are_reverified_and_never_pruned(self):
        self.publish()
        previous = dict(self.s3.objects)
        self.publish()
        self.assertTrue(previous.items() <= self.s3.objects.items())
        self.assertEqual(2, sum(k.endswith('/complete.json') for k in self.s3.objects))
        self.assertFalse(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_failure_after_marker_put_can_be_reverified(self):
        original = self.s3.__call__
        def interrupted(command, **kwargs):
            args = command[command.index('s3api') + 1:]
            if args[0] == 'get-object' and args[args.index('--key') + 1].endswith('/complete.json'):
                raise subprocess.CalledProcessError(1, command)
            return original(command, **kwargs)
        with patch.object(publish.subprocess, 'run', side_effect=interrupted):
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        self.assertTrue(any(k.endswith('/complete.json') for k in self.s3.objects))
        self.publish()
        self.assertEqual(2, sum(k.endswith('/complete.json') for k in self.s3.objects))

    def test_realistic_egress_estimate_and_pre_network_failure(self):
        entries = [{'size': 40_000_000}] * 15
        estimate = publish.egress_estimate(entries, 4000)
        self.assertGreater(estimate, 600_000_000)
        self.assertLess(estimate, 620_000_000)
        with self.assertRaises(ValueError):
            self.publish(egress=1)
        self.assertFalse(self.s3.calls)
        with self.assertRaises(ValueError):
            self.publish(attestations=('true', 'false'))
        self.assertFalse(self.s3.calls)

    def test_budget_and_upload_failure(self):
        with self.assertRaises(ValueError):
            self.publish(budget=100)
        self.assertFalse(self.s3.objects)
        self.s3.fail_put = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assertFalse(self.s3.objects)

    def test_readback_failure_never_marks_complete(self):
        self.s3.corrupt = True
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(any(k.endswith('/complete.json') for k in self.s3.objects))
        with self.assertRaises(ValueError):
            self.publish()

    def test_unknown_and_missing_parts_block_publication(self):
        self.s3.objects['database/v1/../evil'] = b'x'
        with self.assertRaises(ValueError):
            self.publish()
        self.s3.objects.clear()
        self.publish()
        part = next(k for k in self.s3.objects if k.endswith('.gpgpart'))
        del self.s3.objects[part]
        with self.assertRaises(ValueError):
            self.publish()

    def test_four_runs_keep_newest_three_and_capacity_blocks_before_pruning(self):
        order = []
        for _ in range(5):
            before = set(self.s3.objects)
            self.publish()
            new = set(self.s3.objects) - before
            order.append(next(k.split('/')[2] for k in new if k.endswith('/complete.json')))
        self.assertEqual(set(order[-3:]), {k.split('/')[2] for k in self.s3.objects})
        before = dict(self.s3.objects)
        with self.assertRaisesRegex(ValueError, 'storage budget'):
            self.publish(budget=sum(map(len, before.values())) + 100)
        self.assertEqual(before, self.s3.objects)

    def test_v2_and_timestamp_ambiguity_block(self):
        self.publish()
        key = next(k for k in self.s3.objects if k.endswith('/complete.json'))
        marker = json.loads(self.s3.objects[key])
        marker['created_utc'] = '9999-01-01T00:00:00.000000Z'
        marker['hmac_sha256'] = publish.marker_signature(self.secret, marker)
        self.s3.objects[key] = json.dumps(marker).encode()
        before = dict(self.s3.objects)
        with self.assertRaisesRegex(ValueError, 'time'):
            self.publish()
        self.assertEqual(before, self.s3.objects)
        marker = {'version': 2, 'manifest_sha256': marker['manifest_sha256'],
                  'signature_sha256': marker['signature_sha256']}
        marker['hmac_sha256'] = publish.signature(self.secret, key.split('/')[2], marker['manifest_sha256'], marker['signature_sha256'])
        self.s3.objects[key] = json.dumps(marker).encode()
        before = dict(self.s3.objects)
        with self.assertRaisesRegex(ValueError, 'unsupported marker'):
            self.publish()
        self.assertEqual(before, self.s3.objects)

    def test_missing_attestation_never_deletes(self):
        for _ in range(3):
            self.publish()
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            self.publish(attestations=('true', 'true', 'false'))
        self.assertEqual(before, self.s3.objects)
        self.assertFalse(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_marker_identity_is_bound_to_run_and_hmac(self):
        self.publish()
        key = next(k for k in self.s3.objects if k.endswith('/complete.json'))
        marker = json.loads(self.s3.objects[key])
        self.assertEqual(key.split('/')[2], marker['run_id'])
        self.assertEqual(3, marker['version'])
        marker['run_id'] = 'f' * 32
        self.s3.objects[key] = json.dumps(marker).encode()
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(before, self.s3.objects)

    def test_interrupted_prune_preserves_three_and_blocks_next_run(self):
        for _ in range(3):
            self.publish()
        original = self.s3.__call__
        deletes = 0
        def fail_second_delete(command, **kwargs):
            nonlocal deletes
            if 'delete-object' in command:
                deletes += 1
                if deletes == 2:
                    raise subprocess.CalledProcessError(1, command)
            return original(command, **kwargs)
        with patch.object(publish.subprocess, 'run', side_effect=fail_second_delete):
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        complete = [k for k in self.s3.objects if k.endswith('/complete.json')]
        self.assertGreaterEqual(len(complete), 3)
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(before, self.s3.objects)

    def test_tampered_marker_blocks(self):
        self.publish()
        marker = next(k for k in self.s3.objects if k.endswith('/complete.json'))
        data = json.loads(self.s3.objects[marker])
        data['hmac_sha256'] = '0' * 64
        self.s3.objects[marker] = json.dumps(data).encode()
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(before, self.s3.objects)

    def test_tampered_prior_bytes_block_without_deletion(self):
        self.publish()
        part = next(k for k in self.s3.objects if k.endswith('.gpgpart'))
        self.s3.objects[part] = b'x' * len(self.s3.objects[part])
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual(before, self.s3.objects)
        self.assertFalse(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_concurrent_writer_blocks_publication(self):
        original = self.s3.__call__
        listings = 0
        def concurrent(command, **kwargs):
            nonlocal listings
            if 'list-objects-v2' in command:
                listings += 1
                if listings == 2:
                    self.s3.objects['external'] = b'x'
            return original(command, **kwargs)
        with patch.object(publish.subprocess, 'run', side_effect=concurrent):
            with self.assertRaisesRegex(ValueError, 'inventory changed'):
                self.publish()
        self.assertFalse(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_bad_manifest_name(self):
        manifest = json.loads((self.root / 'manifest.json').read_text())
        manifest['parts'][0]['name'] = '../secret'
        (self.root / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(self.s3.calls)


if __name__ == '__main__':
    unittest.main()
