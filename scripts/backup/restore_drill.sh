#!/usr/bin/env bash
# Hermetic local restore drill for the data-only backup contract.
#
# Usage:
#   scripts/backup/restore_drill.sh SOURCE_URL TARGET_URL [--passphrase-file FILE]
#
# SOURCE_URL is the quiescent local database to dump. TARGET_URL must point at a
# different, freshly migrated local database (for example a second isolated
# `supabase db start` project). Only loopback hosts are accepted. An ephemeral
# GPG key pair and passphrase are created unless --passphrase-file is supplied.
# URLs and secrets are never printed.
set -euo pipefail
umask 077

usage() {
  cat >&2 <<'EOF'
Usage: restore_drill.sh SOURCE_URL TARGET_URL [--passphrase-file FILE]

Both URLs must use a loopback host (localhost, 127.0.0.1 or ::1). The target
must be a different database with the repository migrations already applied and
no application rows. The optional passphrase file must be owned by the current
user with mode 0600; otherwise an ephemeral passphrase is generated.
EOF
}

passphrase_file=${BACKUP_GPG_PASSPHRASE_FILE:-}
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --passphrase-file)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      passphrase_file=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 2
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done
[[ ${#positional[@]} -eq 2 ]] || { usage; exit 2; }
source_url=${positional[0]}
target_url=${positional[1]}

for tool in pg_dump psql gpg python3 awk diff; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
done

# Parse in Python so malformed or remote URLs fail before any connection.
parse_url() {
  local url=$1
  local -a fields
  mapfile -d '' fields < <(python3 - "$url" <<'PY'
import sys
import urllib.parse

raw = sys.argv[1]
try:
    parsed = urllib.parse.urlsplit(raw)
    if parsed.scheme not in ('postgres', 'postgresql'):
        raise ValueError
    if parsed.query or parsed.fragment:
        raise ValueError
    host = (parsed.hostname or '').lower()
    if host not in ('localhost', '127.0.0.1', '::1'):
        raise ValueError
    port = parsed.port or 5432
    if not 1 <= port <= 65535:
        raise ValueError
    user = urllib.parse.unquote(parsed.username or '')
    password = urllib.parse.unquote(parsed.password or '')
    database = urllib.parse.unquote(parsed.path.lstrip('/'))
    if not user or not database or '/' in database:
        raise ValueError
except (ValueError, UnicodeError):
    sys.exit(1)
for value in (host, str(port), user, password, database):
    sys.stdout.write(value + '\0')
PY
)
  [[ ${#fields[@]} -eq 5 ]] || return 1
  DRILL_HOST=${fields[0]}
  DRILL_PORT=${fields[1]}
  DRILL_USER=${fields[2]}
  DRILL_PASSWORD=${fields[3]}
  DRILL_DATABASE=${fields[4]}
}

if ! parse_url "$source_url"; then
  echo 'Source URL is invalid or is not a loopback PostgreSQL URL.' >&2
  exit 1
fi
source_identity="$DRILL_HOST:$DRILL_PORT:$DRILL_DATABASE"
if ! parse_url "$target_url"; then
  echo 'Target URL is invalid or is not a loopback PostgreSQL URL.' >&2
  exit 1
fi
target_identity="$DRILL_HOST:$DRILL_PORT:$DRILL_DATABASE"
if [[ "$source_identity" == "$target_identity" ]]; then
  echo 'Source and target must be different local databases.' >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/educador-restore-drill.XXXXXX")
cleanup() {
  if [[ -n "${GNUPGHOME:-}" && -d "$GNUPGHOME" ]]; then
    gpgconf --kill gpg-agent >/dev/null 2>&1 || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

use_conn() {
  local url=$1
  parse_url "$url" || {
    echo 'Database URL rejected.' >&2
    exit 1
  }
  export PGHOST="$DRILL_HOST" PGPORT="$DRILL_PORT" PGUSER="$DRILL_USER" PGDATABASE="$DRILL_DATABASE"
  export PGCONNECT_TIMEOUT=5 PGAPPNAME=educador-restore-drill
  unset PGSERVICE PGSERVICEFILE PGOPTIONS PGSSLMODE PGSSLROOTCERT PGSSLCERT PGSSLKEY
  if [[ -n "$DRILL_PASSWORD" ]]; then
    export PGPASSWORD="$DRILL_PASSWORD"
  else
    unset PGPASSWORD
  fi
}

if [[ -n "$passphrase_file" ]]; then
  [[ -f "$passphrase_file" ]] || { echo 'Passphrase file does not exist.' >&2; exit 1; }
  [[ $(stat -c '%u %a' "$passphrase_file") == "$(id -u) 600" ]] || {
    echo 'Passphrase file must be owned by the current user with mode 0600.' >&2
    exit 1
  }
else
  passphrase_file="$work/passphrase"
  python3 -c 'import secrets; print(secrets.token_hex(32))' > "$passphrase_file"
  chmod 600 "$passphrase_file"
fi

export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --yes --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'EducaDor Drill Signer <drill-signer@example.invalid>' ed25519 sign 0
gpg --batch --quiet --yes --pinentry-mode loopback --passphrase-file "$passphrase_file" \
  --quick-generate-key 'EducaDor Drill Recipient <drill-recipient@example.invalid>' rsa2048 encr 0
key_fingerprint() {
  gpg --batch --with-colons --list-keys "$1" 2>/dev/null |
    awk -F: '$1 == "fpr" { print $10; exit }'
}
signer=$(key_fingerprint 'drill-signer@example.invalid')
recipient=$(key_fingerprint 'drill-recipient@example.invalid')
[[ "$signer" =~ ^[0-9A-F]{40}$ && "$recipient" =~ ^[0-9A-F]{40}$ ]] || {
  echo 'Could not establish drill signing keys.' >&2
  exit 1
}

snapshot() {
  local url=$1
  local destination=$2
  local sqlfile="$work/snapshot-$RANDOM.sql"
  use_conn "$url"
  cat > "$sqlfile" <<'SQL'
\pset tuples_only on
\pset format unaligned
\pset fieldsep '\t'
\pset pager off
SELECT format(
  'SELECT %L, count(*), coalesce(md5(string_agg(md5(x::text), '''' ORDER BY md5(x::text))), md5('''')) FROM %I.%I x',
  n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname IN ('public', 'auth')
  AND NOT (n.nspname = 'auth' AND c.relname = 'schema_migrations')
ORDER BY 1
\gexec
SQL
  psql -X -v ON_ERROR_STOP=1 -f "$sqlfile" > "$destination"
  rm -f -- "$sqlfile"
}

echo 'Checking target is a freshly migrated database.'
snapshot "$target_url" "$work/target-before.tsv"
grep -q '^public\.' "$work/target-before.tsv" || {
  echo 'Target has no public tables; apply the repository migrations first.' >&2
  exit 1
}
if awk -F '\t' '$1 ~ /^public\./ && $2 != 0 { found = 1 } END { exit found ? 0 : 1 }' \
  "$work/target-before.tsv"; then
  echo 'Target already has application rows; use a freshly migrated database.' >&2
  exit 1
fi

echo 'Dumping data-only public and auth tables from source.'
use_conn "$source_url"
pg_dump --no-owner --no-acl --data-only --schema=public --schema=auth \
  --exclude-table-data=auth.schema_migrations --file "$work/dump.sql"
snapshot "$source_url" "$work/source.tsv"
grep -q '^public\.' "$work/source.tsv" || {
  echo 'Source has no public tables; it does not look like an EducaDor database.' >&2
  exit 1
}

echo 'Packing and signing the dump.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 "$script_dir/archive.py" pack "$work/dump.sql" "$work/archive" \
  --recipient "$recipient" --signer "$signer"
rm -f -- "$work/dump.sql"

echo 'Unpacking with the passphrase file.'
BACKUP_GPG_PASSPHRASE_FILE="$passphrase_file" \
  python3 "$script_dir/archive.py" unpack "$work/archive" "$work/restored.sql" --signer "$signer"

echo 'Restoring into the fresh target.'
use_conn "$target_url"
psql -X -v ON_ERROR_STOP=1 -f "$work/restored.sql" >/dev/null

snapshot "$target_url" "$work/target-after.tsv"
if diff -u "$work/source.tsv" "$work/target-after.tsv" > "$work/comparison.diff"; then
  tables=$(wc -l < "$work/source.tsv")
  auth_users=$(awk -F '\t' '$1 == "auth.users" { print $2 }' "$work/target-after.tsv")
  echo "Drill passed: $tables public/auth tables match; auth.users rows restored: ${auth_users:-0}."
else
  echo 'Restore comparison failed (table, row count, content hash):' >&2
  sed -n '1,120p' "$work/comparison.diff" >&2
  exit 1
fi
