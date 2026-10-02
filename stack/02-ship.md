# 02 – Ship (hosting + CI + roadmap + costs + fallbacks)

## PWA hosting (Cloudflare Pages, `app.educador.rgw.app`)

* Staging public build inputs live in `config/staging.public.json`. Build with `flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json`; deploy `build/web` with `CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 npx wrangler pages deploy build/web --project-name=educador --branch=main`. Add `VAPID_PUBLIC_KEY` only when web push is implemented.
* SPA fallback `/* → /index.html` (routes in `lib/core/router.dart` must survive refresh). Headers: `index.html` no-cache, `assets/*` immutable 1y.
* `app.educador.rgw.app` CNAME → `educador-ayp.pages.dev` in the `rgw.app` Cloudflare zone. Public covers served from the public Storage bucket (cached egress). Supabase Auth Site URL: `https://app.educador.rgw.app/`, with invite/password callbacks plus trusted localhost/preview URLs allowed. Publishable key in the bundle is safe with RLS; service-role never in the app. Offline = app shell cached, Supabase reads show offline banner.

* Web push: VAPID keypair (public key in build, private in function secrets) + `firebase-messaging-sw.js` in `build/web`; tokens use the same `fcm_tokens` upsert.

## Planned CI (`.github/workflows/` not yet created, per AGENTS.md secrets rule)

| File | Trigger | Does |
|---|---|---|
| `ci.yml` | PR/push | `flutter analyze`, `flutter test`, `flutter build web` (no deploy) |
| `deploy-pages.yml` | `main` | build web with `--dart-define` secrets → Pages deploy |
| `backup.yml` | weekly cron | `pg_dump` → `educador-backups` bucket (keep newest 3, prune older in same run) |
| `keepalive.yml` | daily cron | light authed query to reset Supabase 7-day pause timer |

Public staging inputs (`SUPABASE_URL`, `SUPABASE_ANON_KEY` publishable key, `CLOUDFLARE_ACCOUNT_ID`) may be versioned; use environment-specific public values for other projects. True secrets (Actions, never in repo): `CLOUDFLARE_API_TOKEN, SUPABASE_DB_URL` (with password). Function secrets (Supabase dashboard): `VAPID_PRIVATE_KEY, FCM_SERVICE_ACCOUNT_JSON, STORAGE_S3_*`; the managed Supabase service-role key stays server-side. PR previews point at the staging project.

## Build order

1. Supabase project + foundation migrations + `20260930000003_multi_context_content.sql` (multi-context onboarding, service-role grants and content controls) + RLS; verify with `supabase/tests/multi_context.sql` and `supabase/tests/content_access.sql`, seed staging from `mock_data.dart` only when test users exist, configure Auth redirect URLs and hook. No public self-signup; follow `03-onboarding.md` for manual-link invites and first-gestor bootstrap.
2. `AuthRepository` + context selection/session restoration + admin-only `invite-member` and `accept-invite`; onboard company managers and employees with one identity across companies.
3. Storage buckets + `storage-*-url` functions; test 25MB PDF/MP3 upload.
4. Live content catalog using the consolidated migration: platform pause/audience, company-wide employee pause, guarded metadata and atomic YouTube publishing with cover upload and responsible professional. Verify `supabase/tests/content_access.sql` as well as multi-context RLS. Company Content replaces the Gestores main tab; manager management lives under Profile. `CourseRepository` powers the live employee catalog/outline through RLS; playback, PDF/audio uploads and quiz authoring still follow player/storage/editor work. `AddCompanyScreen`/`AddEmployeeScreen` create invites via Edge Functions.
5. `ProgressRepository` upsert + certificate fn → `RewardsScreen`/`EmployeeProgressScreen`.
6. Live Gestor dashboard/company/report queries are implemented in
   `20261001000000_gestor_data.sql`; verify `supabase/tests/gestor_data.sql` before
   an operator-approved staging migration. Metric semantics live in
   `01-backend.md#gestor-data-integration`. Client-side CSV export remains deferred.
7. Pages + domain + FCM tokens + `push-on-assign` + 4 workflows + keepalive.

Each step keeps the app runnable on mocks until its repo is swapped.
