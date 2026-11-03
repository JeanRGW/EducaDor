# Delivery automation

## Scope and safety boundaries

- `ci.yml`: every PR and push to main runs Flutter dependency-lock validation, analyze, the full test suite and a release offline-first web build using only `config/staging.public.json`. A separate job runs all Node tests in `scripts/` and `supabase/tests/`, and recursively discovers Deno Edge Function unit tests (including `issue-certificate/request_test.ts`). No application secret or hosted service is needed. Deno runs without runtime permissions; tests must mock external calls.
- `database.yml`: existing isolated local Supabase schema/regression checks, now bounded to 20 minutes with per-ref cancellation. It never targets the hosted database.
- `deploy-pages.yml`: manual dispatch only, main only, environment `pages-production`. Builds and tests main before deploying to the existing Cloudflare Pages project `educador`, production branch `main`. No push, PR, workflow-run, or schedule trigger deploys anything.
- `keepalive.yml`: manual dispatch only, main only, environment `database-keepalive`. Scheduling is deliberately absent until an operator explicitly approves it in a follow-up PR.
- Backups remain deferred pending operator decisions about destination, retention, and credentials. This PR does not implement or claim backup coverage.

New workflow actions are pinned by commit; Flutter is pinned to the locally verified stable 3.47.5, Node to 24.21.0, Deno to 2.9.8, and Wrangler to 4.157.0. Version upgrades should be reviewed together with local verification. Existing database action versions are unchanged. PR concurrency cancels superseded validation, while operational jobs queue rather than cancel midway. All workflows use read-only repository permissions and job timeouts.

## Operator setup (not performed by this change)

Before any operational dispatch, create and protect these GitHub environments. A YAML environment name alone does **not** enforce approval: GitHub can create an unprotected environment automatically. Require reviewers, prevent self-approval where supported, and restrict deployment branches to protected main. If the repository plan does not support the required protection, do not provision credentials or dispatch until an equivalent approval boundary is agreed.

### Pages

1. Create `pages-production` with the protections above.
2. Add environment secret `CLOUDFLARE_API_TOKEN`, scoped to the existing account with only the Pages edit permissions required for deployment. Public account ID `785b73d97c037eb906aae65de518cad6` is in the workflow; it is not a secret.
3. Review the public Supabase configuration, existing Pages project/domain, Auth redirect allowlist, SPA fallbacks, and cache rules before first deployment. This workflow does not alter those provider settings or deploy database/Edge Functions.
4. After merge, confirm required CI and database checks passed on the exact main revision. An authorized operator may then manually dispatch **Deploy Pages (manual)** from main and approve its environment. This PR must not be used as authorization to deploy.
5. Confirm custom-domain route refreshes (`/contexts`, `/invite/accept`, `/set-password`) and the installed PWA against the deployed revision after a separately authorized deployment. No hosted smoke check is run here.

### Database keepalive

1. Create `database-keepalive` with the protections above.
2. Set environment variable `SUPABASE_URL` to the reviewed project HTTPS origin, without path or query. Add environment secret `SUPABASE_SERVICE_ROLE_KEY` using the existing server-only legacy service-role JWT. Do not use anon/publishable keys, user passwords, or add anon table grants.
3. The service-role JWT is the existing credential compatible with both PostgREST headers and the existing schema. It is privileged and bypasses RLS: there is no dedicated restricted machine role in the current project. Keep it confined to this environment and the single request step. The workflow creates no new DB role, grants, RPC, or persistent token. A future restricted credential needs a separate security-reviewed schema design; do not confuse a bounded request with a least-privilege credential.
4. After separate operator authorization, dispatch **Database keepalive (manual)** on main. Missing configuration fails before a request. The script performs `GET /rest/v1/profiles?select=id&limit=1` authenticated with the server credential, rejecting redirects and timing out after 15 seconds. Only HTTP 200 plus an expected table JSON array is accepted (an empty table is valid). Neither returned IDs, response bodies, URL, nor credentials are logged.
5. This executes a real bounded SQL-backed table read, unlike an Auth or HTTP health ping. It does not guarantee Supabase will never pause the project: verify provider inactivity rules and dashboard activity before relying on it. A paused project may need explicit operator restoration; the script does not restore or mutate anything.
6. Daily scheduling is **not enabled**. To enable later, obtain explicit operator approval, review credential exposure and provider policy, add a daily UTC schedule in a follow-up PR, adjust the workflow trigger regression test, and decide how scheduled runs interact with environment review requirements (unattended runs can remain waiting for approval). Monitor run failures. Do not remove protection just to make scheduling unattended.

## Local verification

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test --concurrency=2
flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json
node --test scripts/*test.mjs supabase/tests/*.test.mjs
deno test supabase/functions/
actionlint
```

The keepalive tests inject a local mock fetch; they never contact Supabase. They cover the exact bounded request and headers, empty results, missing credentials, unsafe URL inputs, redirects/HTTP failures, malformed response data, and diagnostic redaction. Workflow contract tests guard manual-only operation, main/environment gates, pinned actions, bounded runtime, and secret-free PR validation; actionlint supplies YAML and Actions expression validation.

The baseline format check fails: Dart reports three existing files needing formatting (`lib/data/mock/mock_data.dart`, `lib/features/auth/onboarding_screens.dart`, and `lib/shared/widgets/logo.dart`). No format gate is added and no repository-wide formatting changes belong in this delivery change. Local logs are kept under ignored `.buildlog/delivery/`. In shared worktree environments serialize heavy Flutter checks with the common `.flutter-validation.lock`; GitHub jobs run on separate machines and need no filesystem lock.
