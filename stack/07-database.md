# Declarative database workflow

## Source of truth

Edit `supabase/schemas/`, not the live database or historical migrations:

- `public/tables/`: final columns, constraints, indexes, RLS policies and grants.
- `public/functions/`: one current definition per RPC/helper, including permissions.
- `public/views/`: guarded report views and permissions. These intentionally use
  owner reads with explicit active-context predicates so company managers can read
  aggregates without access to the underlying lesson contents.
- `public/schema.sql`, `adp_wipes.sql`, `default_privileges.sql`: schema access and
  explicit privilege defaults. No automatic client grants; every public table has
  RLS and explicit permissions. Clients never receive TRUNCATE (which bypasses RLS).
- `_cluster/extensions/`: extensions; `storage/tables/objects.sql`: our Storage
  policies, not a replacement definition of Supabase's managed table.

The `.pgdelta-export.json` file describes the initial export; the engine resolves
dependencies automatically. New objects may be added without hand-ordering files.
Do not add Supabase-managed Auth/Storage tables or hosted `ensure_rls` event triggers.

The CLI is pinned to **2.122.0** in `scripts/db.sh` and database CI.
`[experimental.pgdelta].enabled = true` selects the declarative engine. Do not add
legacy `schema_paths`. Review CLI upgrades together with export/diff changes.

## Change, generate, review, apply

```bash
npx --yes supabase@2.122.0 db start
# Edit supabase/schemas/...sql
bash scripts/db.sh generate meaningful_change_name
# Review supabase/migrations/<timestamp>_meaningful_change_name.sql
bash scripts/db.sh reset
bash scripts/db.sh check
bash scripts/db.sh test
```

`generate` runs `db schema declarative sync --no-apply --strict-coverage`, comparing
desired files against migration history, **not** the live database. Do not use
`db diff`, which ignores declarative files with this engine. `check` detects missing
migrations without writing files. `reset` and `test` are deliberately local-only;
tests run via psql in `supabase_db_EducaDor` and abort on SQL errors. All fixtures
roll back. To retain local data, use `npx --yes supabase@2.122.0 migration up --local`
instead of reset after reviewing the migration.

Review renames, drops, grants, security-definer functions and dependency ordering.
Do not rewrite a deployed migration. Rollbacks are new forward migrations generated
from a reverted desired schema, with destructive SQL reviewed explicitly.

`.github/workflows/database.yml` builds the database from scratch, checks drift,
runs all SQL regression suites and tests the invitation handler. It never deploys.

## Data is separate from DDL

The old nine migrations were retired during the explicitly approved pre-production
wipe. New installations use a generated `*_declarative_baseline.sql` and an explicit
`*_storage_buckets.sql` provisioning migration. They are **not** an incremental
upgrade path for a database still containing the retired objects/history.

Storage buckets are rows, so the engine does not track their MIME types, visibility
or size limits. Change them with a new reviewed DML migration. Bucket object bytes
must be managed through the Storage API, never by deleting `storage.objects` rows.
Do not put INSERT/UPDATE/DELETE data statements in `supabase/schemas/`.

`supabase/seed.sql` is optional demo data derived from `mock_data.dart`, requires
its three Auth identities first, and is disabled by default. It is not required
for an empty installation. SQL tests create independent Auth fixtures; never run
them against staging. Bootstrap the real first gestor with the operator script.

## Normal hosted deployment

```bash
npx --yes supabase@2.122.0 link --project-ref lrlqmkamgncdgppyqnvu
npx --yes supabase@2.122.0 db push --linked --dry-run
# After operator approval and review:
npx --yes supabase@2.122.0 db push --linked
```

Migrations do not deploy Edge Functions, Auth URL settings or secrets. Keep existing
server-only credentials and the passthrough `public.custom_access_token_hook` enabled.
Never push local `config.toml` settings to hosted Auth without reviewing the diff.

## Exceptional pre-production wipe

**Destructive and operator-only. Never make this a CI deploy step.** Confirm the
project ref, ownership and scope before each run. The approved target for this
cutover is EducaDor App, `lrlqmkamgncdgppyqnvu` (`sa-east-1`). Accounts, uploaded
files and application rows are disposable; public configuration/Function secrets
are retained. The old history remains recoverable from Git, not as duplicate SQL.

1. Validate a clean local reset, zero declarative drift and every SQL suite first.
2. Empty all three `educador-*` buckets through the Storage API/CLI. Include the
   backup bucket; do not leave old dumps containing removed user data.
3. Reset the linked database with the replacement migrations (after confirming
   the linked ref): `npx --yes supabase@2.122.0 db reset --linked --no-seed --yes`.
   Do not use migration repair to pretend the new baseline ran on existing objects.
4. Independently verify Auth is empty after reset, deleting any remaining users
   with the server-only Auth Admin API (old authorship references could otherwise
   block deletion before the reset). The pinned CLI cleared hosted Auth users in
   this cutover; do not assume the same behavior across CLI versions. A database
   reset is not a substitute for deleting stored object bytes through Storage.
5. Verify zero rows in all application tables, zero Auth users/Storage objects,
   exactly the new migration history, expected bucket configuration, function
   permissions, and unchanged Auth hook/redirect settings. Do not run fixture tests
   on the hosted project.
6. Re-run `scripts/bootstrap_gestor.py` with a trusted operator-held service-role
   key to create the first account, then use invitations. Never print credentials
   or bearer invitation links into CI/agent logs. No demo data is auto-restored.

Cutover verified on 2026-10-30: the linked project has only migrations
`20261030163135` (generated baseline) and `20261030163136` (Storage provisioning).
All application tables, Auth users and Storage objects were empty, all 15 tables
had RLS enabled, client TRUNCATE grants were absent, and a fresh hosted export
matched the new migration baseline. The first gestor was not auto-recreated.

References: [declarative schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas),
[feature overview](https://supabase.com/features/declarative-schemas).
