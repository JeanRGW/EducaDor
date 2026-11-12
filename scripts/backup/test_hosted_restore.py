import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import hosted_restore

DUMP = """--
-- PostgreSQL database dump
--
SET statement_timeout = 0;
COPY public.courses (id, title) FROM stdin;
1\tFirst
2\tSecond
\\.
COPY public.empty_table (id) FROM stdin;
\\.
COPY auth.users (id, email) FROM stdin;
1\tone@example.test
\\.
"""

RUN = 'a' * 32
CREATED = '2020-11-12T03:17:00.000000Z'
URL = 'postgresql://postgres.abcdefghijklmnopqrst:super-secret-password@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require'


def base_env():
    return {
        'BACKUP_S3_ENDPOINT': 'https://s3.us-east-005.backblazeb2.com',
        'AWS_DEFAULT_REGION': 'us-east-005',
        'BACKUP_HMAC_KEY_HEX': 'ab' * 32,
        'BACKUP_SIGNER_FINGERPRINT': 'A' * 40,
        'BACKUP_PUBLIC_KEY': 'public encryption key',
        'BACKUP_SIGNING_PUBLIC_KEY': 'public signing key',
        'BACKUP_GPG_PASSPHRASE_FILE': '/secure/passphrase',
        'BACKUP_GPG_PASSPHRASE': 'correct horse battery staple',
        'BACKUP_GPG_PRIVATE_KEY': 'private key material',
        'BACKUP_EXPECTED_PROJECT_REF': 'abcdefghijklmnopqrst',
        'PGDATABASE': URL,
        'AWS_ACCESS_KEY_ID': 'access-key-id',
        'AWS_SECRET_ACCESS_KEY': 'aws-secret-value',
    }


class CopyCountsTest(unittest.TestCase):
    def test_copy_blocks_are_counted_and_empty_tables_are_zero(self):
        self.assertEqual({
            ('public', 'courses'): 2,
            ('public', 'empty_table'): 0,
            ('auth', 'users'): 1,
        }, hosted_restore.copy_counts(DUMP))

    def test_escaped_newlines_do_not_add_rows(self):
        dump = 'COPY public.notes (body) FROM stdin;\nline one\\nline two\n\\.\n'
        self.assertEqual({('public', 'notes'): 1}, hosted_restore.copy_counts(dump))

    def test_quoted_identifiers_and_no_data_are_supported(self):
        dump = 'COPY "public"."Course" ("id") FROM stdin;\n\\.\n'
        self.assertEqual({('public', 'Course'): 0}, hosted_restore.copy_counts(dump))

    def test_unterminated_copy_block_is_rejected(self):
        with self.assertRaises(hosted_restore.DrillError):
            hosted_restore.copy_counts('COPY public.courses (id) FROM stdin;\n1\n')

    def test_dump_without_copy_blocks_has_no_tables(self):
        self.assertEqual({}, hosted_restore.copy_counts('-- empty dump\n'))


class CombinedSqlTest(unittest.TestCase):
    def test_single_transaction_truncates_public_and_auth_then_loads_dump(self):
        sql = hosted_restore.build_combined_sql(
            [('public', 'courses'), ('auth', 'users'), ('auth', 'schema_migrations')], DUMP)
        self.assertTrue(sql.startswith('BEGIN;\n'))
        self.assertTrue(sql.endswith('COMMIT;\n'))
        self.assertIn('TRUNCATE TABLE "public"."courses" CASCADE;', sql)
        self.assertIn('TRUNCATE TABLE "auth"."users" CASCADE;', sql)
        self.assertNotIn('schema_migrations', sql)
        truncate = sql.index('TRUNCATE TABLE')
        load = sql.index('COPY public.courses')
        self.assertLess(truncate, load)
        self.assertIn(DUMP.rstrip('\n'), sql)

    def test_identifiers_are_quoted(self):
        sql = hosted_restore.build_combined_sql([('public', 'weird"name')], '')
        self.assertIn('TRUNCATE TABLE "public"."weird""name" CASCADE;', sql)

    def test_other_schemas_are_not_truncated(self):
        sql = hosted_restore.build_combined_sql([('storage', 'objects'), ('public', 'courses')], '')
        self.assertNotIn('storage', sql)
        self.assertIn('public', sql)

    def test_row_counts_are_checked_before_commit(self):
        sql = hosted_restore.build_combined_sql(
            [('public', 'courses'), ('public', 'empty_table')], DUMP,
            {('public', 'courses'): 2, ('public', 'empty_table'): 0})
        self.assertIn('DO $educador_restore$', sql)
        self.assertIn('IF actual <> 2 THEN RAISE EXCEPTION', sql)
        self.assertIn('IF actual <> 0 THEN RAISE EXCEPTION', sql)
        self.assertLess(sql.index('COPY public.courses'), sql.index('DO $educador_restore$'))
        self.assertLess(sql.index('DO $educador_restore$'), sql.index('COMMIT;'))


class ProjectRefTest(unittest.TestCase):
    def test_pooler_and_direct_hosts_expose_the_ref(self):
        self.assertEqual('abcdefghijklmnopqrst', hosted_restore.project_ref(URL))
        direct = 'postgresql://postgres:pw@db.abcdefghijklmnopqrst.supabase.co:5432/postgres'
        self.assertEqual('abcdefghijklmnopqrst', hosted_restore.project_ref(direct))

    def test_matching_expected_ref_is_accepted(self):
        hosted_restore.check_project_ref(URL, 'abcdefghijklmnopqrst')

    def test_environment_project_ref_is_accepted(self):
        url = ('postgresql://postgres.lrlqmkamgncdgppyqnvu:pw'
               '@aws-0-sa-east-1.pooler.supabase.com:5432/postgres?sslmode=require')
        hosted_restore.check_project_ref(url, 'lrlqmkamgncdgppyqnvu')

    def test_conflicting_ref_sources_are_refused(self):
        url = ('postgresql://postgres.aaaaaaaaaaaaaaaa:pw'
               '@db.bbbbbbbbbbbbbbbb.supabase.co:5432/postgres')
        with self.assertRaisesRegex(hosted_restore.DrillError, 'cannot determine'):
            hosted_restore.check_project_ref(url, 'aaaaaaaaaaaaaaaa')

    def test_mismatched_or_unknown_ref_is_refused(self):
        with self.assertRaisesRegex(hosted_restore.DrillError, 'does not match'):
            hosted_restore.check_project_ref(URL, 'zyxwvutsrqponmlkjihg')
        with self.assertRaisesRegex(hosted_restore.DrillError, 'cannot determine'):
            hosted_restore.check_project_ref('postgresql://postgres:pw@db.example.test/postgres',
                                             'abcdefghijklmnopqrst')

    def test_invalid_expected_ref_is_refused(self):
        with self.assertRaisesRegex(hosted_restore.DrillError, 'not a valid project ref'):
            hosted_restore.check_project_ref(URL, '../wrong')

    def test_unset_expected_ref_is_not_checked(self):
        hosted_restore.check_project_ref(URL, '')


class SelectionTest(unittest.TestCase):
    def test_newest_authenticated_v3_run_is_selected(self):
        older, newer = 'a' * 32, 'b' * 32
        objects = {
            f'database/v1/{older}/complete.json': 1,
            f'database/v1/{newer}/complete.json': 1,
            f'database/v1/{newer}/manifest.json': 1,
        }
        with tempfile.TemporaryDirectory() as temporary:
            def confirmed(run, listed, secret, signer, root, require_v3=False):
                self.assertTrue(require_v3)
                return [], {'a' * 32: '2020-11-11T03:17:00.000000Z',
                            'b' * 32: '2020-11-12T03:17:00.000000Z'}[run]
            with patch.object(hosted_restore.publish, 'confirmed', side_effect=confirmed):
                run, created = hosted_restore.newest_authenticated(
                    objects, b'x' * 32, 'A' * 40, Path(temporary))
        self.assertEqual(newer, run)
        self.assertEqual('2020-11-12T03:17:00.000000Z', created)

    def test_duplicate_timestamps_and_unknown_objects_fail_closed(self):
        objects = {f'database/v1/{"a" * 32}/complete.json': 1, f'database/v1/{"b" * 32}/complete.json': 1}
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(hosted_restore.publish, 'confirmed',
                              return_value=([], '2020-11-12T03:17:00.000000Z')):
                with self.assertRaisesRegex(hosted_restore.DrillError, 'ambiguous'):
                    hosted_restore.newest_authenticated(objects, b'x' * 32, 'A' * 40, Path(temporary))
            with self.assertRaisesRegex(hosted_restore.DrillError, 'unknown object'):
                hosted_restore.newest_authenticated({'evil': 1}, b'x' * 32, 'A' * 40, Path(temporary))


class RestoreDrillTest(unittest.TestCase):
    def run_dry(self, env):
        output, error = io.StringIO(), io.StringIO()
        with patch.object(hosted_restore.publish, 'inventory', return_value={}):
            with patch.object(hosted_restore, 'newest_authenticated', return_value=(RUN, CREATED)):
                with patch.object(hosted_restore.publish, 'retrieve') as retrieve:
                    def unpack(source, destination, signer):
                        Path(destination).write_text(DUMP, encoding='utf-8')
                    with patch.object(hosted_restore.archive, 'unpack', side_effect=unpack):
                        with patch.object(hosted_restore, 'run_psql', side_effect=AssertionError('database used')):
                            with patch.object(hosted_restore.sys, 'stdout', output), \
                                 patch.object(hosted_restore.sys, 'stderr', error):
                                code = hosted_restore.main(['--dry-run'], env=env)
        return code, output.getvalue(), error.getvalue(), retrieve

    def test_dry_run_prints_counts_and_never_uses_the_database(self):
        code, output, error, retrieve = self.run_dry(base_env())
        self.assertEqual(0, code)
        self.assertEqual('', error)
        self.assertIn('public.courses\t2', output)
        self.assertIn('public.empty_table\t0', output)
        self.assertIn('auth.users\t1', output)
        self.assertIn('TOTAL\t3', output)
        self.assertIn('Dry run only: no database connection was made.', output)
        retrieve.assert_called_once()

    def test_dry_run_does_not_need_a_database_url(self):
        env = base_env()
        del env['PGDATABASE']
        code, output, _, _ = self.run_dry(env)
        self.assertEqual(0, code)
        self.assertIn('TOTAL\t3', output)

    def test_project_ref_mismatch_refuses_before_network_or_database(self):
        env = base_env() | {'BACKUP_EXPECTED_PROJECT_REF': 'zyxwvutsrqponmlkjihg'}
        error = io.StringIO()
        with patch.object(hosted_restore.publish, 'inventory') as inventory, \
             patch.object(hosted_restore.sys, 'stderr', error):
            code = hosted_restore.main([], env=env)
        self.assertEqual(1, code)
        inventory.assert_not_called()
        self.assertIn('does not match', error.getvalue())
        self.assertNotIn(URL, error.getvalue())
        self.assertNotIn('super-secret-password', error.getvalue())

    def test_failures_never_echo_secrets_or_urls(self):
        env = base_env()
        error = io.StringIO()
        with patch.object(hosted_restore.publish, 'inventory', side_effect=ValueError(URL)), \
             patch.object(hosted_restore.sys, 'stderr', error):
            code = hosted_restore.main([], env=env)
        self.assertEqual(1, code)
        for secret in ('super-secret-password', URL, 'ab' * 32, 'correct horse battery staple',
                       'private key material', 'aws-secret-value'):
            self.assertNotIn(secret, error.getvalue())

    def test_psql_failure_does_not_echo_command_or_stderr(self):
        result = subprocess.CompletedProcess([], 1, b'', ('COPY public.courses, line 1: ' + URL).encode())
        with patch.object(hosted_restore.subprocess, 'run', return_value=result):
            with self.assertRaises(hosted_restore.DrillError) as raised:
                hosted_restore.run_psql(URL, [])
        self.assertNotIn('super-secret-password', str(raised.exception))
        self.assertNotIn(URL, str(raised.exception))
        self.assertIn('rolled back', str(raised.exception))


class CountComparisonTest(unittest.TestCase):
    def test_missing_table_and_count_mismatch_are_reported(self):
        expected = {('public', 'courses'): 2, ('public', 'empty_table'): 0}
        actual = {('public', 'courses'): 1, ('public', 'other'): 4}
        mismatches = hosted_restore.compare_counts(expected, actual)
        self.assertEqual(3, len(mismatches))
        self.assertTrue(any('courses' in item and 'expected 2' in item for item in mismatches))
        self.assertTrue(any('empty_table' in item and 'missing' in item for item in mismatches))
        self.assertTrue(any('other' in item and 'expected 0' in item for item in mismatches))

    def test_matching_counts_pass(self):
        counts = {('public', 'courses'): 2, ('auth', 'users'): 1}
        self.assertEqual([], hosted_restore.compare_counts(counts, dict(counts)))

    def test_schema_migrations_is_ignored(self):
        self.assertEqual([], hosted_restore.compare_counts({}, {('auth', 'schema_migrations'): 9}))


if __name__ == '__main__':
    unittest.main()
