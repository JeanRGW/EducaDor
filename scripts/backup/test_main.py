import os
import unittest
from unittest.mock import patch

import publish


class MainTest(unittest.TestCase):
    def setUp(self):
        self.env = {
            'BACKUP_S3_ENDPOINT': 'https://s3.us-east-005.backblazeb2.com',
            'AWS_DEFAULT_REGION': 'us-east-005',
            'BACKUP_EGRESS_BUDGET_BYTES': '21000000',
            'BACKUP_HMAC_KEY_HEX': 'ab' * 32,
            'BACKUP_SIGNER_FINGERPRINT': 'A' * 40,
            'BACKUP_TOTAL_BUDGET_BYTES': '100000',
            'BACKUP_NON_BACKUP_RESERVE_BYTES': '100',
        }

    def call(self, args, env):
        with patch.dict(os.environ, env, clear=True), patch.object(publish.sys, 'argv', ['publish.py', *args]), \
             patch.object(publish, 'audit') as audit, patch.object(publish, 'publish') as publisher:
            publish.main()
            return audit, publisher

    def test_b2_regions_accepted_and_must_match_signing_region(self):
        for region in ('us-east-005', 'eu-central-003'):
            for suffix in ('', '/'):
                with self.subTest(region=region, suffix=suffix):
                    env = self.env | {'BACKUP_S3_ENDPOINT': f'https://s3.{region}.backblazeb2.com{suffix}',
                                      'AWS_DEFAULT_REGION': region}
                    audit, _ = self.call(['audit'], env)
                    audit.assert_called_once()
        for endpoint in ('https://s3.us-east-005.backblazeb2.com.evil.test',
                         'https://example.storage.supabase.co/storage/v1/s3',
                         'http://s3.us-east-005.backblazeb2.com',
                         'https://s3.us-east-005.backblazeb2.com/path',
                         'https://s3.us-east-005.backblazeb2.com//',
                         'https://s3.eu-central-003.backblazeb2.com'):
            with self.subTest(endpoint=endpoint), self.assertRaises(SystemExit):
                self.call(['audit'], self.env | {'BACKUP_S3_ENDPOINT': endpoint})

    def test_audit_reserved_and_budget_required(self):
        audit, publisher = self.call(['audit'], self.env)
        audit.assert_called_once_with(21000000, bytes.fromhex('ab' * 32), 'A' * 40)
        publisher.assert_not_called()
        audit, publisher = self.call(['./audit'], self.env)
        audit.assert_not_called()
        self.assertEqual(publisher.call_args.args[0], './audit')
        env = dict(self.env)
        del env['BACKUP_EGRESS_BUDGET_BYTES']
        with self.assertRaises(SystemExit):
            self.call(['audit'], env)


if __name__ == '__main__':
    unittest.main()
