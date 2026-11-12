"""Validate the database connection URL before pg_dump runs.

libpq does not expand a postgresql:// URI supplied only through PGDATABASE; a
bare value is treated as a database name and pg_dump falls back to a local Unix
socket. This helper rejects that case, checks the URI structure with
urllib.parse and prints a summary that never contains the URL, user, password
or host values.
"""

from dataclasses import dataclass, field
import os
import sys
from urllib.parse import parse_qs, urlsplit

SUPPORTED_SCHEMES = ('postgres://', 'postgresql://')
EXPECTED_FORM = (
    'postgresql://postgres.<project-ref>:<DB_PASSWORD>@'
    'aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require'
)
SSLMODE_ADVICE = (
    'sslmode is absent. The Supabase pooler requires TLS; append '
    '?sslmode=require (or &sslmode=require when other parameters are present).'
)


@dataclass
class CheckResult:
    scheme: str = 'missing'
    host: bool = False
    port: bool = False
    user: bool = False
    database: bool = False
    sslmode: bool = False
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self):
        return not self.errors


def _missing_database_url():
    return (
        'PGDATABASE is empty. Set BACKUP_DATABASE_URL to the Supabase session '
        f'pooler URL: {EXPECTED_FORM}'
    )


def validate(value):
    """Return a CheckResult for a connection string without echoing it."""
    result = CheckResult()
    if not value:
        result.errors.append(_missing_database_url())
        return result
    if value != value.strip():
        result.errors.append(
            'PGDATABASE has leading or trailing whitespace. Remove the spaces '
            'or newline around the connection URL.'
        )
        return result
    if not value.startswith(SUPPORTED_SCHEMES):
        result.errors.append(
            'PGDATABASE must start with postgresql:// or postgres://. A bare '
            'database name makes pg_dump connect to a local Unix socket instead '
            f'of the database host. Expected: {EXPECTED_FORM}'
        )
        return result

    result.scheme = value.split('://', 1)[0]
    try:
        parts = urlsplit(value)
        host = parts.hostname
        port = parts.port
        username = parts.username
    except ValueError:
        result.errors.append(
            'PGDATABASE is not a valid URI. Check the port (1-65535) and use '
            f'brackets around IPv6 hosts, for example [2001:db8::1]. Expected: {EXPECTED_FORM}'
        )
        return result

    if '@' not in parts.netloc:
        result.errors.append(
            'PGDATABASE is missing user information (no @ in the authority). '
            f'Expected: {EXPECTED_FORM}'
        )
    result.user = bool(username)
    result.host = bool(host)
    result.port = port is not None
    database = parts.path[1:] if parts.path.startswith('/') else parts.path
    result.database = bool(database)

    if not result.host:
        result.errors.append(
            'PGDATABASE is missing the host. Add the pooler host after @, for '
            f'example @aws-0-<region>.pooler.supabase.com:5432. Expected: {EXPECTED_FORM}'
        )
    if not result.database:
        result.errors.append(
            'PGDATABASE is missing the database name. Add /postgres before the '
            f'query string. Expected: {EXPECTED_FORM}'
        )

    sslmode = parse_qs(parts.query, keep_blank_values=True).get('sslmode')
    result.sslmode = bool(sslmode and sslmode[0].strip())
    if not result.sslmode:
        result.warnings.append(SSLMODE_ADVICE)
    return result


def render(result):
    """Render presence flags only; never include values from the URL."""
    lines = [
        f'Database URL check: {"ok" if result.ok else "invalid"}',
        f'  scheme: {result.scheme}',
        f'  host: {"present" if result.host else "missing"}',
        f'  port: {"present" if result.port else "missing"}',
        f'  user: {"present" if result.user else "missing"}',
        f'  path (database): {"present" if result.database else "missing"}',
        f'  sslmode: {"present" if result.sslmode else "missing"}',
    ]
    lines.extend(f'Warning: {warning}' for warning in result.warnings)
    lines.extend(f'Error: {error}' for error in result.errors)
    return '\n'.join(lines)


def main(argv=None, env=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv:
        print('usage: check_db_url.py (reads PGDATABASE)', file=sys.stderr)
        return 2
    env = os.environ if env is None else env
    result = validate(env.get('PGDATABASE', ''))
    print(render(result))
    return 0 if result.ok else 1


if __name__ == '__main__':
    sys.exit(main())
