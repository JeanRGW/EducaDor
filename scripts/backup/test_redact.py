from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

import redact


class RedactTest(unittest.TestCase):
    env = {
        'PGDATABASE': 'postgresql://postgres:s3cr3t-value@db.example.supabase.co:5432/postgres',
        'BACKUP_HMAC_KEY_HEX': 'a1b2c3d4e5f6',
        'BACKUP_SIGNING_PRIVATE_KEY': '-----BEGIN KEY-----\nprivate\n-----END KEY-----',
        'PATH': '/usr/bin',
    }

    def test_removes_full_pgdatabase_value(self):
        text = 'connecting with ' + self.env['PGDATABASE'] + ' failed'
        cleaned = redact.redact(text, self.env)
        self.assertEqual(cleaned, f'connecting with {redact.REDACTED} failed')

    def test_removes_url_password_from_rewritten_url(self):
        text = 'pg_dump: error: connection to postgresql://postgres:hunter2@db.example.co:5432/x failed'
        cleaned = redact.redact(text, self.env)
        self.assertNotIn('hunter2', cleaned)
        self.assertIn('postgresql://postgres:[redacted]@db.example.co:5432/x', cleaned)

    def test_removes_backup_secret_values(self):
        cleaned = redact.redact('key=a1b2c3d4e5f6 and private', self.env)
        self.assertNotIn('a1b2c3d4e5f6', cleaned)

    def test_bounds_output_and_keeps_utf8_intact(self):
        cleaned = redact.redact('é' * 10_000, {'PATH': '/usr/bin'})
        self.assertLessEqual(len(cleaned.encode()), redact.DIAGNOSTIC_LIMIT)
        self.assertEqual(len(cleaned), redact.DIAGNOSTIC_LIMIT // 2)
        self.assertNotIn('\ufffd', cleaned)

    def test_drops_partial_secret_cut_by_read_limit(self):
        secret = self.env['BACKUP_HMAC_KEY_HEX']
        cleaned = redact.redact('context ' + secret[:5], self.env)
        self.assertTrue(cleaned.endswith('context '), cleaned)

    def test_render_never_raises_on_missing_file(self):
        self.assertIn('unavailable', redact.render('/nonexistent/pg.err', self.env))


class RedactCliTest(unittest.TestCase):
    def run_cli(self, contents, env):
        directory = tempfile.mkdtemp()
        path = Path(directory, 'pg.err')
        path.write_bytes(contents)
        merged = {**os.environ, **env}
        return subprocess.run([sys.executable, redact.__file__, str(path)],
                              capture_output=True, text=True, env=merged, check=True)

    def test_cli_prints_redacted_diagnostic_with_advice(self):
        env = {'PGDATABASE': 'postgresql://postgres:s3cr3t-value@db.example.co:5432/postgres',
               'BACKUP_HMAC_KEY_HEX': 'a1b2c3d4e5f6'}
        error = ('pg_dump: error: connection to server at "db.example.co" (2001:db8::1), '
                 'port 5432 failed: Network is unreachable\n'
                 'connection string postgresql://postgres:s3cr3t-value@db.example.co/postgres\n'
                 'token a1b2c3d4e5f6\n')
        result = self.run_cli(error.encode(), env)
        for secret in ('s3cr3t-value', 'a1b2c3d4e5f6', env['PGDATABASE']):
            self.assertNotIn(secret, result.stdout)
            self.assertNotIn(secret, result.stderr)
        self.assertIn(redact.REDACTED, result.stdout)
        self.assertIn('Network is unreachable', result.stdout)
        self.assertIn('?sslmode=require', result.stdout)
        body = result.stdout.split('\n', 1)[1].rsplit(redact.ADVICE, 1)[0]
        self.assertLessEqual(len(body.encode()), redact.DIAGNOSTIC_LIMIT + 1)

    def test_cli_bounds_oversized_stderr(self):
        result = self.run_cli(b'x' * (redact.DIAGNOSTIC_LIMIT * 4), {})
        self.assertLessEqual(len(result.stdout.encode()), 2 * redact.DIAGNOSTIC_LIMIT)
        self.assertEqual(result.stdout.count('x'), redact.DIAGNOSTIC_LIMIT)


if __name__ == '__main__':
    unittest.main()
