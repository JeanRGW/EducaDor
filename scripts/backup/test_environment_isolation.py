"""Verify subprocess environments never inherit unrelated backup secrets."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import archive
import publish

SECRETS = ('BACKUP_DATABASE_URL', 'BACKUP_SIGNING_PRIVATE_KEY', 'BACKUP_HMAC_KEY_HEX',
           'BACKUP_S3_SECRET_ACCESS_KEY', 'BACKUP_PUBLIC_KEY')
AWS = {'PATH': '/usr/bin', 'AWS_CONFIG_FILE': '/tmp/config', 'AWS_SHARED_CREDENTIALS_FILE': '/tmp/creds',
       'AWS_ACCESS_KEY_ID': 'test', 'AWS_SECRET_ACCESS_KEY': 'test', 'AWS_DEFAULT_REGION': 'us-east-005'}


class IsolationTest(unittest.TestCase):
    def test_aws_never_receives_database_hmac_or_signing_secrets(self):
        captured = {}
        def run(command, **kwargs):
            captured['env'] = kwargs['env']
            kwargs['stdout'].write(b'{"Contents": []}')
            return subprocess.CompletedProcess(command, 0)
        with patch.dict(os.environ, AWS | {k: 'secret' for k in SECRETS}
                        | {'BACKUP_S3_ENDPOINT': 'https://test.storage.supabase.co/storage/v1/s3'}, clear=True), \
             patch.object(publish.subprocess, 'run', side_effect=run):
            publish.inventory()
        self.assertTrue(set(captured['env']) <= set(AWS))
        self.assertEqual(captured['env']['AWS_DEFAULT_REGION'], 'us-east-005')
        self.assertFalse(set(captured['env']) & set(SECRETS))
        self.assertNotIn('GNUPGHOME', captured['env'])

    def test_archive_subprocess_never_receives_database_or_aws_secrets(self):
        captured = {}
        class Stream:
            def read(self, _=None):
                return b''
            def close(self):
                pass
        def popen(args, **kwargs):
            captured['env'] = kwargs['env']
            return type('P', (), {'stdout': Stream(), 'wait': lambda s: 0, 'kill': lambda s: None})()
        with patch.dict(os.environ, AWS | {k: 'secret' for k in SECRETS}, clear=True), \
             patch.object(archive.subprocess, 'Popen', side_effect=popen):
            archive.run_output(['true'], Path(tempfile.gettempdir()) / 'unused', 10)
        self.assertTrue(set(captured['env']) <= {'PATH', 'HOME', 'GNUPGHOME', 'LANG', 'LC_ALL'})
        self.assertFalse(set(captured['env']) & set(SECRETS))


if __name__ == '__main__':
    unittest.main()
