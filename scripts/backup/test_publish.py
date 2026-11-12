from datetime import datetime, timedelta
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
        publish.publish(self.root, budget, reserve, egress + 11_000_000, self.secret, attestations, 'A' * 40, daily=1, weekly=1)

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
        self.assertEqual(set(order[-2:]), {k.split('/')[2] for k in self.s3.objects})
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
        self.assertEqual(before, self.s3.objects)

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
        self.assertGreaterEqual(len(complete), 2)
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

    def test_gfs_distinct_days_and_iso_weeks(self):
        start = datetime(2025, 1, 13, 12)
        times = {str(i): (start - timedelta(days=i)).strftime('%Y-%m-%dT%H:%M:%S.%fZ') for i in range(35)}
        times['duplicate-day'] = '2025-01-13T01:00:00.000000Z'
        selected = publish.survivors_for(times, 7, 4)
        self.assertEqual(set(map(str, range(7))) | {'8', '15'}, selected)
        self.assertNotIn('duplicate-day', selected)
        self.assertEqual((2025, 1), datetime.strptime(times['14'], '%Y-%m-%dT%H:%M:%S.%fZ').isocalendar()[:2])

    def test_daily_weekly_publication_across_iso_year_rollover(self):
        class Clock(datetime):
            current = None

            @classmethod
            def now(cls, tz=None):
                return cls.current.replace(tzinfo=tz)

        start = datetime(2024, 12, 15, 12)
        runs_by_date = {}
        with patch.object(publish, 'datetime', Clock):
            for offset in range(35):
                Clock.current = start + timedelta(days=offset)
                before = set(self.s3.objects)
                publish.publish(self.root, 100000, 100, 32_000_000, self.secret,
                                ('true', 'true', 'true'), 'A' * 40, daily=7, weekly=4)
                created = set(self.s3.objects) - before
                run = next(key.split('/')[2] for key in created if key.endswith('/complete.json'))
                runs_by_date[Clock.current.date().isoformat()] = run

        # Jan 12 is ISO 2025-W02; Dec 29 belongs to ISO 2024-W52.
        dates = {'2025-01-12', '2025-01-13', '2025-01-14', '2025-01-15',
                 '2025-01-16', '2025-01-17', '2025-01-18', '2025-01-05', '2024-12-29'}
        expected = {f'{publish.PREFIX}{runs_by_date[day]}/{name}' for day in dates
                    for name in ('complete.json', 'manifest.json', 'manifest.sig', '0000.gpgpart')}
        self.assertEqual(expected, set(self.s3.objects))
        self.assertTrue(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_run_cap_fails_without_deletion(self):
        for i in range(publish.MAX_RUNS):
            self.s3.objects[f'{publish.PREFIX}{i:032x}/complete.json'] = b'x'
        before = dict(self.s3.objects)
        with self.assertRaisesRegex(ValueError, 'too many prior runs'):
            publish.publish(self.root, 100000, 100, 32_000_000, self.secret,
                            ('true', 'true', 'true'), 'A' * 40, daily=7, weekly=4)
        self.assertEqual(before, self.s3.objects)
        self.assertFalse(any(op == 'delete-object' for op, _ in self.s3.calls))

    def test_pruning_reads_candidate_metadata_not_body(self):
        self.publish()
        oldest = next(k.split('/')[2] for k in self.s3.objects if k.endswith('/complete.json'))
        self.publish()
        self.s3.calls.clear()
        self.publish()
        calls = self.s3.calls
        reads = [args[args.index('--key') + 1] for op, args in calls if op == 'get-object']
        self.assertNotIn(f'{publish.PREFIX}{oldest}/0000.gpgpart', reads)
        self.assertGreaterEqual(reads.count(f'{publish.PREFIX}{oldest}/complete.json'), 2)
        self.assertTrue(any(op == 'delete-object' and oldest in args[args.index('--key') + 1] for op, args in calls))

    def test_audit_detects_old_corruption_and_egress(self):
        self.publish()
        self.publish()
        self.s3.calls.clear()
        with self.assertRaises(ValueError):
            publish.audit(1, self.secret, 'A' * 40)
        self.assertFalse(self.s3.calls)
        publish.audit(21_000_000, self.secret, 'A' * 40)
        part = next(k for k in self.s3.objects if k.endswith('.gpgpart'))
        self.s3.objects[part] = b'x' * len(self.s3.objects[part])
        before = dict(self.s3.objects)
        with self.assertRaises(ValueError):
            publish.audit(21_000_000, self.secret, 'A' * 40)
        self.assertEqual(before, self.s3.objects)

    def test_bad_manifest_name(self):
        manifest = json.loads((self.root / 'manifest.json').read_text())
        manifest['parts'][0]['name'] = '../secret'
        (self.root / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(self.s3.calls)


if __name__ == '__main__':
    unittest.main()
