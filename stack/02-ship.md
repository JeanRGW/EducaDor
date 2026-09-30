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

1. Supabase project + schema + `20260923000000_multi_context.sql` + `20260925000000_service_role_grants.sql` + RLS; verify multi-context RLS with `supabase/tests/multi_context.sql`, seed staging from `mock_data.dart` only when test users exist, configure Auth redirect URLs and hook. No public self-signup; follow `03-onboarding.md` for manual-link invites and first-gestor bootstrap.
2. `AuthRepository` + context selection/session restoration + admin-only `invite-member` and `accept-invite`; onboard company managers and employees with one identity across companies.
3. Storage buckets + `storage-*-url` functions; test 25MB PDF/MP3 upload.
4. `CourseRepository` (courses/modules/lessons/assignments) → `AddTrailScreen` writes through RLS; employees learn only in the `funcionario` context. `AddCompanyScreen`/`AddEmployeeScreen` create invites via Edge Functions.
5. `ProgressRepository` upsert + certificate fn → `RewardsScreen`/`EmployeeProgressScreen`.
6. Report views + `charts.dart`, CSV export client-side.
7. Pages + domain + FCM tokens + `push-on-assign` + 4 workflows + keepalive.

Each step keeps the app runnable on mocks until its repo is swapped.
