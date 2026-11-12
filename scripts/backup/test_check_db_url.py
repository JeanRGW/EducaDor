import io
import unittest
from contextlib import redirect_stderr, redirect_stdout

import check_db_url

VALID = (
    'postgresql://postgres.abcdefghijklmnop:p%40ss%3Aword%2Fwith%23chars'
    '@aws-0-sa-east-1.pooler.supabase.com:5432/postgres?sslmode=require'
)


class CheckDbUrlTest(unittest.TestCase):
    def assert_ok(self, value):
        result = check_db_url.validate(value)
        self.assertTrue(result.ok, result.errors)
        return result

    def assert_invalid(self, value, fragment):
        result = check_db_url.validate(value)
        self.assertFalse(result.ok)
        self.assertTrue(any(fragment in error for error in result.errors),
                        result.errors)
        return result

    def test_accepts_valid_session_pooler_url(self):
        result = self.assert_ok(VALID)
        self.assertEqual(result.scheme, 'postgresql')
        self.assertTrue(result.host)
        self.assertTrue(result.port)
        self.assertTrue(result.user)
        self.assertTrue(result.database)
        self.assertTrue(result.sslmode)
        self.assertEqual(result.warnings, [])

    def test_accepts_postgres_scheme(self):
        result = self.assert_ok(
            'postgres://postgres.ref:secret@db.example.com:5432/postgres?sslmode=require'
        )
        self.assertEqual(result.scheme, 'postgres')

    def test_rejects_bare_database_name(self):
        result = self.assert_invalid('postgres', 'must start with postgresql://')
        self.assertEqual(result.scheme, 'missing')
        self.assertIn('local Unix socket', result.errors[0])

    def test_rejects_missing_scheme(self):
        self.assert_invalid(
            'postgres.ref:secret@db.example.com:5432/postgres?sslmode=require',
            'must start with postgresql://',
        )

    def test_rejects_missing_host(self):
        result = self.assert_invalid(
            'postgresql://user:secret@/postgres?sslmode=require', 'missing the host'
        )
        self.assertFalse(result.host)

    def test_rejects_missing_host_without_user_info(self):
        self.assert_invalid(
            'postgresql://postgres', 'missing user information'
        )

    def test_rejects_missing_database_name(self):
        result = self.assert_invalid(
            'postgresql://user:secret@db.example.com:5432/?sslmode=require',
            'missing the database name',
        )
        self.assertFalse(result.database)

    def test_rejects_empty_value(self):
        self.assert_invalid('', 'PGDATABASE is empty')

    def test_rejects_surrounding_whitespace(self):
        self.assert_invalid(VALID + '\n', 'leading or trailing whitespace')

    def test_rejects_invalid_port_or_ipv6_syntax(self):
        self.assert_invalid(
            'postgresql://user:secret@db.example.com:notaport/postgres',
            'not a valid URI',
        )
        self.assert_invalid(
            'postgresql://user:secret@2001:db8::1:5432/postgres',
            'not a valid URI',
        )

    def test_accepts_percent_encoded_password_with_special_characters(self):
        result = self.assert_ok(VALID)
        self.assertTrue(result.user)
        self.assertTrue(result.database)

    def test_accepts_ipv6_host(self):
        result = self.assert_ok(
            'postgresql://user:secret@[2001:db8::1]:5432/postgres?sslmode=require'
        )
        self.assertTrue(result.host)
        self.assertTrue(result.port)

    def test_sslmode_absent_warns_but_is_accepted(self):
        result = self.assert_ok(
            'postgresql://user:secret@db.example.com:5432/postgres'
        )
        self.assertFalse(result.sslmode)
        self.assertTrue(any('sslmode=require' in warning for warning in result.warnings))

    def test_empty_sslmode_warns(self):
        result = self.assert_ok(
            'postgresql://user:secret@db.example.com:5432/postgres?sslmode='
        )
        self.assertFalse(result.sslmode)
        self.assertTrue(result.warnings)

    def test_sslmode_present_has_no_warning(self):
        result = self.assert_ok(VALID)
        self.assertTrue(result.sslmode)
        self.assertEqual(result.warnings, [])

    def test_render_never_echoes_values(self):
        result = check_db_url.validate(VALID)
        output = check_db_url.render(result)
        self.assertIn('scheme: postgresql', output)
        for marker in ('host: present', 'port: present', 'user: present',
                       'path (database): present', 'sslmode: present'):
            self.assertIn(marker, output)
        for secret in ('p%40ss', 'p@ss', 'aws-0-sa-east-1', 'postgres.abcdefghijklmnop',
                       'secret', VALID):
            self.assertNotIn(secret, output)

    def test_render_never_echoes_values_on_invalid_input(self):
        value = 'postgresql://user:s3cr3t@db.example.com:notaport/postgres'
        output = check_db_url.render(check_db_url.validate(value))
        self.assertIn('Database URL check: invalid', output)
        for secret in ('s3cr3t', 'db.example.com', value):
            self.assertNotIn(secret, output)

    def test_main_reads_environment_and_returns_status(self):
        stream = io.StringIO()
        with redirect_stdout(stream):
            status = check_db_url.main([], env={'PGDATABASE': VALID})
        self.assertEqual(status, 0)
        output = stream.getvalue()
        self.assertIn('Database URL check: ok', output)
        self.assertNotIn('p%40ss', output)
        self.assertNotIn('aws-0-sa-east-1', output)

        stream = io.StringIO()
        with redirect_stdout(stream):
            status = check_db_url.main([], env={'PGDATABASE': 'postgres'})
        self.assertEqual(status, 1)
        output = stream.getvalue()
        self.assertIn('Database URL check: invalid', output)
        self.assertNotIn('postgres\n', output)

    def test_main_rejects_arguments(self):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(check_db_url.main(['postgresql://secret']), 2)
        self.assertIn('usage:', errors.getvalue())
        self.assertNotIn('secret', errors.getvalue())


REF = 'abcdefghijklmnop'
POOLER_URL = (
    'postgresql://postgres.abcdefghijklmnop:SuperSecretPw'
    '@aws-0-sa-east-1.pooler.supabase.com:5432/postgres?sslmode=require'
)
DIRECT_URL = (
    'postgresql://postgres:SuperSecretPw'
    '@db.abcdefghijklmnop.supabase.co:5432/postgres?sslmode=require'
)

SECRET_MARKERS = ('SuperSecretPw', 'aws-0-sa-east-1',
                  'db.abcdefghijklmnop.supabase.co',
                  'postgres.abcdefghijklmnop')


class ProjectRefTest(unittest.TestCase):
    def validate(self, value, expected=None):
        return check_db_url.validate(value, expected)

    def assert_no_secrets(self, output):
        for marker in SECRET_MARKERS:
            self.assertNotIn(marker, output)

    def test_derives_ref_from_session_pooler_username(self):
        result = self.validate(POOLER_URL)
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.project_ref, REF)

    def test_derives_ref_from_direct_host(self):
        result = self.validate(DIRECT_URL)
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.project_ref, REF)

    def test_direct_host_is_case_insensitive(self):
        result = self.validate(
            'postgresql://postgres:SuperSecretPw'
            '@DB.ABCDEFGHIJKLMNOP.SUPABASE.CO:5432/postgres?sslmode=require'
        )
        self.assertEqual(result.project_ref, REF)

    def test_ipv6_host_without_ref_is_unknown(self):
        result = self.validate(
            'postgresql://user:SuperSecretPw@[2001:db8::1]:5432/postgres?sslmode=require'
        )
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.project_ref, 'unknown')

    def test_generic_host_and_user_are_unknown(self):
        result = self.validate(
            'postgresql://postgres:SuperSecretPw@db.example.com:5432/postgres?sslmode=require'
        )
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.project_ref, 'unknown')

    def test_unknown_forms_are_unknown(self):
        for value in (
            'postgresql://admin.abcdefghijklmnop:SuperSecretPw@db.example.com:5432/postgres',
            'postgresql://postgres.:SuperSecretPw@db.example.com:5432/postgres',
            'postgresql://postgres:SuperSecretPw@db..supabase.co:5432/postgres',
            'postgresql://postgres:SuperSecretPw@db.abcdefghijklmnop.example.com:5432/postgres',
            'postgresql://postgres:SuperSecretPw@db.abc-def.supabase.co:5432/postgres',
            'postgres',
            '',
        ):
            with self.subTest(value=value):
                self.assertEqual(self.validate(value).project_ref, 'unknown')

    def test_conflicting_sources_are_unknown(self):
        result = self.validate(
            'postgresql://postgres.aaaaaaaaaaaaaaaa:SuperSecretPw'
            '@db.bbbbbbbbbbbbbbbb.supabase.co:5432/postgres?sslmode=require'
        )
        self.assertTrue(result.ok, result.errors)
        self.assertEqual(result.project_ref, 'unknown')

    def test_matching_expected_ref_is_accepted(self):
        result = self.validate(POOLER_URL, REF)
        self.assertTrue(result.ok, result.errors)
        result = self.validate(DIRECT_URL, REF)
        self.assertTrue(result.ok, result.errors)

    def test_mismatching_expected_ref_fails_closed(self):
        result = self.validate(POOLER_URL, 'zzzzzzzzzzzzzzzz')
        self.assertFalse(result.ok)
        message = ' '.join(result.errors)
        self.assertIn('BACKUP_EXPECTED_PROJECT_REF=zzzzzzzzzzzzzzzz', message)
        self.assertIn(f'({REF})', message)
        self.assert_no_secrets(check_db_url.render(result))

    def test_expected_ref_with_unknown_derivation_fails_closed(self):
        result = self.validate(
            'postgresql://user:SuperSecretPw@[2001:db8::1]:5432/postgres?sslmode=require',
            REF,
        )
        self.assertFalse(result.ok)
        self.assertIn('cannot be derived', ' '.join(result.errors))
        self.assert_no_secrets(check_db_url.render(result))

    def test_unset_or_blank_expected_ref_is_not_checked(self):
        for expected in (None, '', '   '):
            with self.subTest(expected=expected):
                result = self.validate(
                    'postgresql://postgres:SuperSecretPw@db.example.com:5432/postgres',
                    expected,
                )
                self.assertTrue(result.ok, result.errors)

    def test_render_prints_project_ref_only(self):
        result = self.validate(POOLER_URL, REF)
        output = check_db_url.render(result)
        self.assertIn(f'project_ref={REF}', output)
        self.assert_no_secrets(output)
        self.assertNotIn(POOLER_URL, output)

        output = check_db_url.render(self.validate(
            'postgresql://user:SuperSecretPw@[2001:db8::1]:5432/postgres?sslmode=require'
        ))
        self.assertIn('project_ref=unknown', output)
        self.assert_no_secrets(output)

    def test_main_compares_expected_ref_from_environment(self):
        stream = io.StringIO()
        with redirect_stdout(stream):
            status = check_db_url.main([], env={
                'PGDATABASE': POOLER_URL,
                'BACKUP_EXPECTED_PROJECT_REF': REF,
            })
        self.assertEqual(status, 0)
        output = stream.getvalue()
        self.assertIn(f'project_ref={REF}', output)
        self.assert_no_secrets(output)

        stream = io.StringIO()
        with redirect_stdout(stream):
            status = check_db_url.main([], env={
                'PGDATABASE': POOLER_URL,
                'BACKUP_EXPECTED_PROJECT_REF': 'zzzzzzzzzzzzzzzz',
            })
        self.assertEqual(status, 1)
        output = stream.getvalue()
        self.assertIn('Database URL check: invalid', output)
        self.assertIn('BACKUP_EXPECTED_PROJECT_REF', output)
        self.assert_no_secrets(output)

    def test_main_accepts_unset_or_blank_expected_ref(self):
        for env in ({'PGDATABASE': POOLER_URL},
                    {'PGDATABASE': POOLER_URL,
                     'BACKUP_EXPECTED_PROJECT_REF': '   '}):
            with self.subTest(env=env):
                stream = io.StringIO()
                with redirect_stdout(stream):
                    status = check_db_url.main([], env=env)
                self.assertEqual(status, 0)
                self.assertIn(f'project_ref={REF}', stream.getvalue())


if __name__ == '__main__':
    unittest.main()
