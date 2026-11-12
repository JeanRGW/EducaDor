# 02 – Ship (hosting + CI + roadmap + costs + fallbacks)

## PWA hosting (Cloudflare Pages, `app.educador.rgw.app`)

* Staging public build inputs live in `config/staging.public.json`. Every publishable build must generate the custom static-shell worker after Flutter; the Flutter flag alone does not provide offline caching. Manual recipe (deployment requires operator approval):

  ```bash
  flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json
  node scripts/generate-shell-worker.mjs build/web
  node --test scripts/pwa/*.test.mjs
  # Operator-approved deployment only:
  CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 npx wrangler pages deploy build/web --project-name=educador --branch=main
  ```

  Add `VAPID_PUBLIC_KEY` only when web push is implemented.
* SPA fallback `/* → /index.html` (routes in `lib/core/router.dart` must survive refresh). Entry points use no-cache; unfingerprinted `assets/*` and CanvasKit revalidate rather than immutable one-year caching. Security headers include a report-only CSP pending real-flow browser validation.
* `app.educador.rgw.app` CNAME → `educador-ayp.pages.dev` in the `rgw.app` Cloudflare zone. Public covers served from the public Storage bucket (cached egress). Supabase Auth Site URL: `https://app.educador.rgw.app/`, with invite/password callbacks plus trusted localhost/preview URLs allowed. Publishable key in the bundle is safe with RLS; service-role never in the app. Offline support is static shell only via the required build-generated custom worker, with a browser `navigator.onLine`/events banner (not an inference from server/Auth errors). Current reads still use per-screen errors/retry; private/Auth/API responses, signed files and bearer URL responses are never cached. Navigation uses the sanitized static index; no offline course data, media or write queue is implemented. See `12-pwa-reliability.md` for lifecycle, browser evidence and limitations.

* Planned web push uses Firebase public configuration and the web VAPID public key in the build; FCM HTTP v1 sends use the server-side service account, not a VAPID private key in Supabase. The messaging worker must coexist with the static-shell worker without caching private, Auth, API or bearer responses. See [round plan](13-security-push-round.md).

## CI

`database.yml` is implemented: isolated database rebuild, declarative drift check,
SQL regressions and invitation-handler tests, without staging credentials or deploy.
The workflows below are listed at the audit baseline. See the
[implementation review](08-implementation-roadmap.md) for PR assignments; an
assigned workflow is not enabled infrastructure unless listed as enabled here.
The backup workflow is activated and gated as described below.

| File | Trigger | Does |
|---|---|---|
| `ci.yml` | PR/push | `flutter analyze`, `flutter test`, `flutter build web` (no deploy) |
| `deploy-pages.yml` | `main` | build web with `--dart-define` secrets → Pages deploy |
| `backup.yml` | daily cron / manual | DB-only `pg_dump` → B2 `educador-backups` (`s3.us-east-005.backblazeb2.com`), daily 7 + weekly 4; enabled, each run gated by `BACKUP_ENABLED` (manual also needs confirm), no object bytes |
| `keepalive.yml` | daily cron | light authed query to reset Supabase 7-day pause timer |

Public staging inputs (`SUPABASE_URL`, `SUPABASE_ANON_KEY` publishable key, `CLOUDFLARE_ACCOUNT_ID`) may be versioned; use environment-specific public values for other projects. True secrets (Actions, never in repo): `CLOUDFLARE_API_TOKEN, SUPABASE_DB_URL` (with password). Function secrets (Supabase dashboard): `FCM_SERVICE_ACCOUNT_JSON, STORAGE_S3_*`; the managed Supabase service-role key stays server-side. Future PR previews must use an explicitly approved staging target; preview automation is not implemented at this baseline.

## Build order

1. Supabase project + generated declarative baseline + Storage provisioning + RLS; follow `07-database.md` and verify with `bash scripts/db.sh check` and `bash scripts/db.sh test`. Seed staging from `mock_data.dart` only when test users exist; configure Auth redirect URLs and hook. No public self-signup; follow `03-onboarding.md` for manual-link invites and first-gestor bootstrap.
2. `AuthRepository` + context selection/session restoration + admin-only `invite-member` and `accept-invite`; onboard company managers and employees with one identity across companies.
3. Storage buckets + `storage-*-url` functions; test 25MB PDF/MP3 upload.
4. Live content catalog under `supabase/schemas/public/`: platform pause/audience, company-wide employee pause, guarded metadata and course-first authoring with covers/responsible professional. Verify `supabase/tests/content_access.sql` and multi-context RLS. Company Content replaces the Gestores main tab; manager management lives under Profile. `EmployeeLearningRepository` powers the live employee catalog/outline. Playback, PDF/audio uploads and quiz authoring are implemented; see `03-content.md`. `AddCompanyScreen`/`AddEmployeeScreen` create invites via Edge Functions.
5. Employee learning screens, guarded `ProgressRepository` saves and
   `issue-certificate` are implemented in `supabase/schemas/public/functions/`
   and Flutter. Verify `supabase/tests/employee_features.sql`, then obtain approval
   before migration → `issue-certificate` deployment → Flutter. The first player
   supported YouTube video; additional formats are now implemented in `03-content.md`.
   Metrics, settings boundaries and review checks are in
   `06-employee-features.md`.
6. Live Gestor dashboard/company/report queries are implemented in
   `supabase/schemas/public/functions/gestor_*.sql`; verify `supabase/tests/gestor_data.sql` before
   an operator-approved staging migration. Metric semantics live in
   `01-backend.md#gestor-data-integration`. Client-side CSV export remains deferred.
7. Gestor lifecycle management uses `supabase/schemas/public/functions/`:
   company edits/pause, accepted gestor directories/revocation, own-profile edits
   and in-place course/video edits. Verify `supabase/tests/gestor_management.sql`
   before an operator-approved migration. Deploy the updated `accept-invite`
   function **after** the migration, then build/deploy Flutter; invitation
   acceptance now requires its server-only atomic RPC.
8. Company-manager data integration uses `supabase/schemas/public/functions/`:
   exact dashboard/profile counts, monthly participation, company-wide highlights
   and searched/paginated employee metadata with company-scoped last activity.
   Verify `supabase/tests/company_data.sql` before operator-approved migration,
   then deploy Flutter. Business definitions and deferred workflows remain
   separate; see `01-backend.md#company-manager-data-integration`.
9. Pages + domain + FCM tokens + `push-on-assign` + 4 workflows + keepalive.

Each step keeps the app runnable on mocks until its repo is swapped.

## Operational decisions before activation

New deploy/keepalive workflows must remain gated until credentials, protected
environments and behavior are reviewed. PR preview automation is not implemented
at the audit baseline. No production target is inferred from the staging config.

B2 backup activation is approved and the scheduled workflow is enabled, gated by
the repository-level `BACKUP_ENABLED` variable and (for manual runs) the `confirm`
input. The remaining operator gates are hosted restore validation, verified B2
lifecycle/versioning, and key custody; DB dumps alone do not back up uploaded
object bytes. See [backup recovery](14-backup-recovery.md).

FCM requires operator-provided Firebase Spark project, service account, public web
configuration/VAPID key, approved web origins and Android configuration, plus
supported-device checks. These are release gates, not completed setup. The event
contract and approval-gated migration → functions → PWA order are in
[the round plan](13-security-push-round.md). Do not deploy from feature PRs.

Corporate video access uses YouTube whitelisting. Paid video services and R2 are
not approved fallbacks under the locked no-card stack. Quota warning/restriction
behavior needs an explicit implementation; documentation is not monitoring.
