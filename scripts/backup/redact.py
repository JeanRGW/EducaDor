"""Bounded, redacted diagnostics for failed pg_dump runs.

pg_dump can echo its connection string, including the password, in stderr. The
backup workflow therefore keeps stderr in the private scratch directory and
only surfaces it through this filter, which removes known secret values from
the environment, strips URL passwords, and caps the amount of output.
"""

import os
import re
import sys

DIAGNOSTIC_LIMIT = 4096
# Read enough that a truncation mid-secret is unlikely, then bound the output.
READ_LIMIT = 256 * 1024
# Values shorter than this are ambiguous and would shred the diagnostic text.
MIN_SECRET_LENGTH = 4
REDACTED = '[redacted]'
URL_PASSWORD = re.compile(r'(postgres(?:ql)?://[^:/@\s]*:)[^@\s]*(@)', re.IGNORECASE)
ADVICE = ('Advice: if the direct database host resolves to IPv6 only, use the '
          'Supabase session pooler URL with ?sslmode=require instead.')


def secret_values(env):
    """Environment values that must never appear in a diagnostic.

    PGDATABASE carries the connection string and every BACKUP_* variable may be
    provisioned as a secret, so all of them are redacted (fail closed).
    """
    values = set()
    for name, value in env.items():
        if not value or len(value) < MIN_SECRET_LENGTH:
            continue
        if name == 'PGDATABASE' or name.startswith('BACKUP_'):
            values.add(value)
    # Longest first so a value containing another one is fully removed.
    return sorted(values, key=len, reverse=True)


def _strip_partial_tail(text, values):
    """Drop a trailing fragment of a secret cut off by a bounded read."""
    for value in values:
        for size in range(len(value) - 1, MIN_SECRET_LENGTH - 1, -1):
            if text.endswith(value[:size]):
                return text[:-size]
    return text


def redact(text, env=None, limit=DIAGNOSTIC_LIMIT):
    """Return text with secret values removed, at most limit encoded bytes."""
    values = secret_values(os.environ if env is None else env)
    text = _strip_partial_tail(text, values)
    for value in values:
        text = text.replace(value, REDACTED)
    text = URL_PASSWORD.sub(lambda match: match.group(1) + REDACTED + match.group(2), text)
    encoded = text.encode('utf-8')
    if len(encoded) > limit:
        # Decode with 'ignore' so a multi-byte character is never split.
        text = encoded[:limit].decode('utf-8', 'ignore')
    return text


def render(path, env=None):
    """Render one diagnostic block for a stderr file, never raising."""
    env = os.environ if env is None else env
    try:
        with open(path, 'rb') as handle:
            raw = handle.read(READ_LIMIT)
    except OSError as error:
        return f'pg_dump stderr unavailable ({type(error).__name__}).'
    body = redact(raw.decode('utf-8', 'replace'), env).strip()
    if not body:
        body = '(pg_dump wrote nothing to stderr)'
    return ('pg_dump diagnostic (redacted, at most 4096 bytes):\n' + body)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print('usage: redact.py <stderr-file>', file=sys.stderr)
        return 2
    print(render(argv[0]))
    print(ADVICE)
    return 0


if __name__ == '__main__':
    sys.exit(main())
