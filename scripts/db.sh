#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Pin the CLI because declarative exports and the diff engine evolve together.
supabase() { npx --yes supabase@2.122.0 "$@"; }

case "${1:-}" in
  generate)
    if [[ -z "${2:-}" ]]; then
      echo 'Usage: bash scripts/db.sh generate change_name' >&2
      exit 1
    fi
    supabase db schema declarative sync --no-apply --strict-coverage -f "$2"
    ;;
  check)
    # sync writes a migration even without -f. Isolate it so CI never edits history.
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/educador-schema-check.XXXXXX")
    trap 'rm -rf -- "$scratch"' EXIT
    mkdir "$scratch/supabase"
    cp supabase/config.toml "$scratch/supabase/"
    cp -R supabase/schemas supabase/migrations "$scratch/supabase/"
    result=$(supabase --workdir "$scratch" db schema declarative sync --no-apply --strict-coverage 2>&1)
    echo "$result"
    grep -q 'No schema changes found' <<< "$result"
    ;;
  test)
    # Never accepts a linked project or remote URL. Fixtures are local-only.
    for file in supabase/tests/*.sql; do
      echo "Testing $file"
      docker exec -i supabase_db_EducaDor \
        psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$file"
    done
    ;;
  reset)
    supabase db reset --local --no-seed
    ;;
  *)
    echo 'Usage: bash scripts/db.sh {generate NAME|check|test|reset}' >&2
    exit 1
    ;;
esac
