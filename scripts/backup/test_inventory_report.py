import contextlib
import io
import os
import unittest
from unittest.mock import patch

import inventory_report
import publish
from test_publish import FakeS3


class InventoryReportTest(unittest.TestCase):
    def setUp(self):
        self.s3 = FakeS3()
        self.runner = patch.object(publish.subprocess, 'run', side_effect=self.s3)
        self.runner.start()
        self.addCleanup(self.runner.stop)
        self.env = patch.dict(os.environ, {
            'BACKUP_S3_ENDPOINT': 'https://s3.us-east-005.backblazeb2.com',
            'AWS_DEFAULT_REGION': 'us-east-005',
        })
        self.env.start()
        self.addCleanup(self.env.stop)

    def report(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(0, inventory_report.main())
        return output.getvalue()

    def test_empty_bucket_is_safe(self):
        self.assertEqual({
            'runs': 0,
            'complete_markers': 0,
            'total_bytes': 0,
            'unknown_or_incomplete': False,
        }, inventory_report.summarize({}))
        self.assertEqual(
            'Backup inventory: runs=0 complete_markers=0 total_bytes=0 unknown_or_incomplete=false\n',
            self.report())

    def test_two_complete_runs(self):
        for run, part in (('a' * 32, b'part'), ('b' * 32, b'other part')):
            base = publish.PREFIX + run + '/'
            self.s3.objects[base + 'complete.json'] = b'marker'
            self.s3.objects[base + 'manifest.json'] = b'manifest'
            self.s3.objects[base + 'manifest.sig'] = b'signature'
            self.s3.objects[base + '0000.gpgpart'] = part
        total = sum(map(len, self.s3.objects.values()))
        self.assertEqual({
            'runs': 2,
            'complete_markers': 2,
            'total_bytes': total,
            'unknown_or_incomplete': False,
        }, inventory_report.summarize(publish.inventory()))
        self.assertEqual(
            f'Backup inventory: runs=2 complete_markers=2 total_bytes={total} '
            'unknown_or_incomplete=false\n',
            self.report())

    def test_incomplete_run_is_flagged(self):
        self.s3.objects[publish.PREFIX + 'c' * 32 + '/0000.gpgpart'] = b'part'
        summary = inventory_report.summarize(publish.inventory())
        self.assertEqual(1, summary['runs'])
        self.assertEqual(0, summary['complete_markers'])
        self.assertTrue(summary['unknown_or_incomplete'])
        self.s3.objects = {publish.PREFIX + 'c' * 32 + '/complete.json': b'marker'}
        summary = inventory_report.summarize(publish.inventory())
        self.assertEqual(1, summary['complete_markers'])
        self.assertTrue(summary['unknown_or_incomplete'])

    def test_unknown_object_is_flagged(self):
        for key in ('outside', f'{publish.PREFIX}not-a-run/complete.json',
                    publish.PREFIX + 'd' * 32 + '/unexpected.bin'):
            with self.subTest(key=key):
                self.s3.objects = {key: b'x'}
                summary = inventory_report.summarize(publish.inventory())
                self.assertTrue(summary['unknown_or_incomplete'])

    def test_listing_error_fails_without_output(self):
        with patch.object(publish.subprocess, 'run', side_effect=OSError('listing failed')):
            output = io.StringIO()
            errors = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(1, inventory_report.main())
        self.assertEqual('', output.getvalue())
        self.assertEqual('Backup inventory listing failed.\n', errors.getvalue())


if __name__ == '__main__':
    unittest.main()
