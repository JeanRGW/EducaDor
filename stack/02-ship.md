# 02 – Ship (hosting + CI + roadmap + costs + fallbacks)

## PWA hosting (Cloudflare Pages, `app.educador.rgw.app`)

* Staging public build inputs live in `config/staging.public.json`. Build with `flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json`; deploy `build/web` with `CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 npx wrangler pages deploy build/web --project-name=educador --branch=main`. Add `VAPID_PUBLIC_KEY` only when web push is implemented.
* SPA fallback `/* → /index.html` (routes in `lib/core/router.dart` must survive refresh). Headers: `index.html` no-cache, `assets/*` immutable 1y.
* `app.educador.rgw.app` CNAME → `educador-ayp.pages.dev` in the `rgw.app` Cloudflare zone. Public covers served from the public Storage bucket (cached egress). Supabase Auth Site URL: `https://app.educador.rgw.app/`, with invite/password callbacks plus trusted localhost/preview URLs allowed. Publishable key in the bundle is safe with RLS; service-role never in the app. Offline-shell caching and a global banner are planned gaps at the audit baseline: the Flutter flag alone does not prove caching. Current reads use per-screen errors/retry; private/Auth/API responses must never be cached by an offline worker.

* Web push: VAPID keypair (public key in build, private in function secrets) + `firebase-messaging-sw.js` in `build/web`; tokens use the same `fcm_tokens` upsert.

## CI

`database.yml` is implemented: isolated database rebuild, declarative drift check,
SQL regressions and invitation-handler tests, without staging credentials or deploy.
The remaining workflows below are planned at the audit baseline. See the
[implementation review](08-implementation-roadmap.md) for PR assignments; an
assigned workflow is not enabled infrastructure.

| File | Trigger | Does |
|---|---|---|
| `ci.yml` | PR/push | `flutter analyze`, `flutter test`, `flutter build web` (no deploy) |
| `deploy-pages.yml` | `main` | build web with `--dart-define` secrets → Pages deploy |
| `backup.yml` | weekly cron | `pg_dump` → `educador-backups` bucket (keep newest 3, prune older in same run) |
| `keepalive.yml` | daily cron | light authed query to reset Supabase 7-day pause timer |

Public staging inputs (`SUPABASE_URL`, `SUPABASE_ANON_KEY` publishable key, `CLOUDFLARE_ACCOUNT_ID`) may be versioned; use environment-specific public values for other projects. True secrets (Actions, never in repo): `CLOUDFLARE_API_TOKEN, SUPABASE_DB_URL` (with password). Function secrets (Supabase dashboard): `VAPID_PRIVATE_KEY, FCM_SERVICE_ACCOUNT_JSON, STORAGE_S3_*`; the managed Supabase service-role key stays server-side. Future PR previews must use an explicitly approved staging target; preview automation is not implemented at this baseline.

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

Backups have an unresolved capacity/security contract: a 500MB database can exceed
the 50MB object cap and three dumps can exceed the shared 1GB Storage allocation.
Compression/chunking needs checksums, encryption/key custody, a total budget and a
tested restore path. DB dumps alone do not back up uploaded lesson objects.

FCM requires operator-provided Firebase/VAPID configuration and an agreed
assignment/certificate event contract. Planned architecture does not imply push
delivery is available. Do not deploy functions or enable jobs from feature PRs.

Corporate video access uses YouTube whitelisting. Paid video services and R2 are
not approved fallbacks under the locked no-card stack. Quota warning/restriction
behavior needs an explicit implementation; documentation is not monitoring.
