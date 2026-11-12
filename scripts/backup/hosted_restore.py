#!/usr/bin/env python3
"""Manual, rollback-safe hosted restore drill for the data-only backup contract.

The drill selects the newest authenticated v3 run in the bucket, verifies its
marker HMAC, manifest signature and every ciphertext part with the existing
publisher helpers, decrypts it with the offline private key, and either reports
the COPY row counts (--dry-run) or replaces all application and Auth rows in one
database transaction. A failure rolls the whole transaction back.

The target database URL is read from PGDATABASE and is never printed. The same
applies to passwords, key material and dump contents.
"""

import argparse
from datetime import datetime, timezone
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

import archive
import check_db_url
import publish

SCHEMAS = ('public', 'auth')
EXCLUDED = {('auth', 'schema_migrations')}
COPY = re.compile(r'^COPY\s+(.+?)(?:\s+\([^)]*\))?\s+FROM stdin;$')
IDENT = re.compile(r'^(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_$]*)$')
PROJECT_REF = re.compile(r'[A-Za-z0-9]{1,64}\Z')
MAX_REPORTED_MISMATCHES = 20


class DrillError(Exception):
    """A failure with a message that is safe to show to the operator."""


def _identifier(value):
    value = value.strip()
    if not IDENT.fullmatch(value):
        raise DrillError('dump contains an unsupported table identifier')
    if value.startswith('"'):
        return value[1:-1].replace('""', '"')
    # PostgreSQL folds unquoted identifiers to lower case.
    return value.lower()


def _relation(value):
    value = value.strip()
    match = re.fullmatch(r'(.+?)\s*\.\s*(.+)', value)
    if not match:
        raise DrillError('dump contains an unsupported table reference')
    return _identifier(match.group(1)), _identifier(match.group(2))


def copy_counts(text):
    """Return {(schema, table): rows} from COPY ... FROM stdin blocks.

    Tables without a COPY block are absent, which callers treat as zero rows.
    Escaped newlines inside a row keep it on one physical line, so counting the
    lines between the COPY header and its terminator is exact.
    """
    counts = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        match = COPY.match(lines[index])
        index += 1
        if not match:
            continue
        relation = _relation(match.group(1))
        rows = 0
        while index < len(lines):
            if lines[index] == '\\.':
                index += 1
                break
            rows += 1
            index += 1
        else:
            raise DrillError('dump contains an unterminated COPY block')
        counts[relation] = counts.get(relation, 0) + rows
    return counts


def dump_counts(path):
    return copy_counts(Path(path).read_text(encoding='utf-8'))


def _quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def _verification_sql(tables, expected):
    """Build an in-transaction row-count guard for every target table."""
    statements = []
    for schema, table in sorted(set(tables) | set(expected)):
        if schema not in SCHEMAS or (schema, table) in EXCLUDED:
            continue
        qualified = f'{_quote_identifier(schema)}.{_quote_identifier(table)}'
        wanted = expected.get((schema, table), 0)
        statements.append(
            f'  SELECT count(*) INTO actual FROM {qualified};\n'
            f"  IF actual <> {wanted} THEN RAISE EXCEPTION 'row count mismatch for "
            f'{schema}.{table}: expected {wanted}, found %\', actual; END IF;')
    if not statements:
        return []
    return ['DO $educador_restore$', 'DECLARE actual bigint;', 'BEGIN',
            *statements, 'END', '$educador_restore$;']


def build_combined_sql(tables, dump, expected=None):
    """Build one transaction: truncate every target table, load, verify, commit."""
    truncates = []
    for schema, table in sorted(set(tables)):
        if schema not in SCHEMAS or (schema, table) in EXCLUDED:
            continue
        truncates.append(f'TRUNCATE TABLE {_quote_identifier(schema)}.{_quote_identifier(table)} CASCADE;')
    body = dump.rstrip('\n')
    verify = _verification_sql(tables, expected) if expected is not None else []
    lines = ['BEGIN;', *truncates, body, *verify, 'COMMIT;']
    return '\n'.join(lines) + '\n'


def project_ref(url):
    """Extract a Supabase project ref without retaining the URL itself."""
    try:
        parts = urlsplit(url)
        username = parts.username or ''
        host = parts.hostname or ''
    except ValueError:
        return None
    if parts.scheme not in ('postgres', 'postgresql'):
        return None
    return check_db_url.derive_project_ref(username, host)


def check_project_ref(url, expected):
    expected = (expected or '').strip()
    if not expected:
        return
    if not PROJECT_REF.fullmatch(expected):
        raise DrillError('BACKUP_EXPECTED_PROJECT_REF is not a valid project ref; refusing the drill')
    actual = project_ref(url)
    if actual is None:
        raise DrillError('cannot determine the database project ref; refusing the hosted drill')
    if actual != expected:
        raise DrillError('database project ref does not match BACKUP_EXPECTED_PROJECT_REF; refusing the hosted drill')


def _psql_env(url):
    return {
        'PATH': os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin'),
        'HOME': os.environ.get('HOME', '/tmp'),
        'PGDATABASE': url,
        'PGCONNECT_TIMEOUT': '15',
        'PGAPPNAME': 'educador-hosted-restore',
    }


def run_psql(url, arguments):
    # The URL is passed explicitly because libpq does not expand a URI supplied
    # only through PGDATABASE. Neither the command nor stderr is printed: COPY
    # errors can echo row data from the dump.
    command = ['psql', '--dbname', url, '--no-psqlrc', '-v', 'ON_ERROR_STOP=1', *arguments]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=_psql_env(url), check=False)
    if result.returncode != 0:
        raise DrillError(f'psql failed with exit code {result.returncode}; changes were rolled back')
    return result.stdout.decode('utf-8', 'replace')


TABLES_SQL = """
SELECT n.nspname, c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND n.nspname IN ('public', 'auth')
  AND NOT (n.nspname = 'auth' AND c.relname = 'schema_migrations')
ORDER BY n.nspname, c.relname;
"""

COUNTS_SQL = """
SELECT n.nspname, c.relname,
       (xpath('/row/c/text()', query_to_xml(
           format('SELECT count(*) AS c FROM %I.%I', n.nspname, c.relname),
           false, true, '')))[1]::text
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND n.nspname IN ('public', 'auth')
  AND NOT (n.nspname = 'auth' AND c.relname = 'schema_migrations')
ORDER BY n.nspname, c.relname;
"""


def _field_relation(schema, table):
    if not schema or not table or any(character in schema + table for character in '\t\r\n'):
        raise DrillError('database returned an unexpected table name')
    return schema, table


def _rows(output):
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split('\t')
        if len(fields) != 2:
            raise DrillError('database returned an unexpected table list')
        yield _field_relation(*fields)


def list_tables(url):
    return list(_rows(run_psql(url, ['-A', '-t', '-F', '\t', '-c', TABLES_SQL])))


def read_counts(url):
    counts = {}
    for line in run_psql(url, ['-A', '-t', '-F', '\t', '-c', COUNTS_SQL]).splitlines():
        if not line:
            continue
        fields = line.split('\t')
        if len(fields) != 3 or not fields[2].isdigit():
            raise DrillError('database returned an unexpected row count')
        counts[_field_relation(fields[0], fields[1])] = int(fields[2])
    return counts


def compare_counts(expected, actual):
    """Return mismatch descriptions; tables absent from the dump expect zero."""
    mismatches = []
    for relation in sorted(set(expected) | set(actual)):
        if relation in EXCLUDED:
            continue
        wanted = expected.get(relation, 0)
        found = actual.get(relation)
        if found is None:
            mismatches.append(f'{relation[0]}.{relation[1]}: missing after restore (expected {wanted})')
        elif wanted != found:
            mismatches.append(f'{relation[0]}.{relation[1]}: expected {wanted}, found {found}')
    return mismatches


def _runs(objects):
    runs = set()
    for key in objects:
        if not key.startswith(publish.PREFIX):
            raise DrillError('bucket contains an unknown object')
        segments = key[len(publish.PREFIX):].split('/')
        if len(segments) != 2 or not publish.RUN.fullmatch(segments[0]):
            raise DrillError('bucket contains an unknown object')
        runs.add(segments[0])
    return runs


def newest_authenticated(objects, secret, signer, root):
    """Authenticate every v3 marker and select the newest run."""
    runs = _runs(objects)
    if not runs:
        raise DrillError('no backup runs found in the bucket')
    times = {}
    for run in sorted(runs):
        _, timestamp = publish.confirmed(run, objects, secret, signer, root, require_v3=True)
        times[run] = timestamp
    if len(set(times.values())) != len(times):
        raise DrillError('backup timestamps are ambiguous; refusing the drill')
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
    if any(timestamp >= now for timestamp in times.values()):
        raise DrillError('backup timestamps are non-monotonic; refusing the drill')
    newest = max(times, key=times.get)
    return newest, times[newest]


def _download_budget(objects):
    # A local bound for the existing retrieve helper; not a provider network cap.
    return max(archive.MAX_TOTAL, sum(objects.values())) + (
        2 * (publish.MANIFEST_LIMIT + publish.SIGNATURE_LIMIT)
        + publish.MARKER_LIMIT + publish.NETWORK_ALLOWANCE)


def _validate_endpoint(env):
    endpoint = env['BACKUP_S3_ENDPOINT']
    match = re.fullmatch(r'https://s3\.([a-z0-9-]+)\.backblazeb2\.com/?', endpoint)
    if not match or env.get('AWS_DEFAULT_REGION') != match.group(1):
        raise DrillError('invalid backup endpoint or mismatched AWS region')


def _report(counts):
    for schema, table in sorted(counts):
        print(f'{schema}.{table}\t{counts[(schema, table)]}')
    print(f'TOTAL\t{sum(counts.values())}')


def drill(args, env):
    if args.dry_run:
        # No database URL is required, but a mismatched one must still be caught
        # before an operator believes a real run would target the right project.
        pass
    else:
        url = env.get('PGDATABASE')
        if not url:
            raise DrillError('PGDATABASE is required for a real restore')
        check_project_ref(url, env.get('BACKUP_EXPECTED_PROJECT_REF'))

    _validate_endpoint(env)
    secret = bytes.fromhex(env['BACKUP_HMAC_KEY_HEX'])
    signer = env['BACKUP_SIGNER_FINGERPRINT']
    objects = publish.inventory()

    with tempfile.TemporaryDirectory(prefix='educador-hosted-restore-') as temporary:
        root = Path(temporary)
        run, created = newest_authenticated(objects, secret, signer, root)
        print(f'Selected newest authenticated run {run} (created {created}).')
        retrieved = root / 'retrieved'
        publish.retrieve(run, retrieved, _download_budget(objects), secret, signer)
        dump_path = root / 'dump.sql'
        archive.unpack(retrieved, dump_path, signer)

        dump = dump_path.read_text(encoding='utf-8')
        expected = copy_counts(dump)
        unexpected = [relation for relation in expected if relation[0] not in SCHEMAS]
        if unexpected:
            raise DrillError('dump contains rows outside the public and auth schemas')
        _report(expected)
        if args.dry_run:
            print('Dry run only: no database connection was made.')
            return

        tables = list_tables(url)
        combined = root / 'combined.sql'
        combined.write_text(build_combined_sql(tables, dump, expected), encoding='utf-8')
        os.chmod(combined, 0o600)
        run_psql(url, ['--single-transaction', '-f', str(combined)])

        actual = read_counts(url)
        mismatches = compare_counts(expected, actual)
        if mismatches:
            for mismatch in mismatches[:MAX_REPORTED_MISMATCHES]:
                print(f'Mismatch: {mismatch}', file=sys.stderr)
            if len(mismatches) > MAX_REPORTED_MISMATCHES:
                print(f'... and {len(mismatches) - MAX_REPORTED_MISMATCHES} more mismatches.', file=sys.stderr)
            raise DrillError('restored row counts do not match the dump')
        print(f'Restore verified: {len(actual)} public/auth tables match the dump.')


def main(argv=None, env=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true',
                        help='verify and unpack the archive, then print COPY row counts only')
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)
    env = os.environ if env is None else env
    try:
        drill(args, env)
        return 0
    except DrillError as error:
        print(f'Hosted restore drill failed: {error}', file=sys.stderr)
        return 1
    except (KeyError, ValueError, TypeError, OSError, subprocess.SubprocessError) as error:
        # Never echo the exception text: external tools may include URLs or row data.
        print(f'Hosted restore drill failed ({type(error).__name__}).', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
