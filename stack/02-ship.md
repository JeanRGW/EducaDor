# 02 – Ship (hosting + CI + roadmap + costs + fallbacks)

## PWA hosting (Cloudflare Pages, `educador.rgw.app`)

* Build in CI: `flutter build web --release --pwa-strategy offline-first --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=VAPID_PUBLIC_KEY=...`; deploy `build/web` via `wrangler pages deploy build/web --project-name=educador`.
* SPA fallback `/* → /index.html` (routes in `lib/core/router.dart` must survive refresh). Headers: `index.html` no-cache, `assets/*` immutable 1y.
* `educador.rgw.app` CNAME → `*.pages.dev` (auto SSL; automatic if `rgw.app` DNS is on Cloudflare). Public covers served from the public Storage bucket (cached egress). Supabase Auth URL config: `Site URL=https://educador.rgw.app` + `localhost` + preview URLs. Anon key in bundle is safe with RLS; service-role never in app. Offline = app shell cached, Supabase reads show offline banner.

* Web push: VAPID keypair (public key in build, private in function secrets) + `firebase-messaging-sw.js` in `build/web`; tokens use the same `fcm_tokens` upsert.

## CI (`.github/workflows/`, per AGENTS.md secrets rule)

| File | Trigger | Does |
|---|---|---|
| `ci.yml` | PR/push | `flutter analyze`, `flutter test`, `flutter build web` (no deploy) |
| `deploy-pages.yml` | `main` | build web with `--dart-define` secrets → Pages deploy |
| `backup.yml` | weekly cron | `pg_dump` → `educador-backups` bucket (keep newest 3, prune older in same run) |
| `keepalive.yml` | daily cron | light authed query to reset Supabase 7-day pause timer |

Secrets (Actions, never in repo): `SUPABASE_URL, SUPABASE_ANON_KEY, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, SUPABASE_DB_URL`. Function secrets (Supabase dashboard): `VAPID_PRIVATE_KEY, FCM_SERVICE_ACCOUNT_JSON, STORAGE_S3_*`. PR previews point at the staging project.

## Build order

1. Supabase project + schema + RLS + seed from `lib/data/mock/mock_data.dart` (generate UUIDs, keep a throwaway mock→uuid map); enable the `custom_access_token_hook` Auth hook in the dashboard; create the 3 test users (one per role) and verify RLS by querying as each.
2. Storage buckets + `storage-*-url` functions; test 25MB PDF/MP3 upload.
3. `AuthRepository` + `session_controller.dart` on Supabase; keep role redirect.
4. `CourseRepository` (courses/modules/lessons/assignments) → `AddTrailScreen`/`AddCompanyScreen`/`AddEmployeeScreen` write through RLS.
5. `ProgressRepository` upsert + certificate fn → `RewardsScreen`/`EmployeeProgressScreen`.
6. Report views + `charts.dart`, CSV export client-side.
7. Pages + domain + FCM tokens + `push-on-assign` + 4 workflows + keepalive.

Each step keeps the app runnable on mocks until its repo is swapped.
