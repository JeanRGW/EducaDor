# AGENTS.md – EducaDor

Flutter training platform. 3 roles: `gestor` (platform admin), `empresa` (company admin, scoped to `company_id`), `funcionario` (employee, scoped to self + company). UI mocks exist in `lib/features/`; backend plan is decided – follow it, do not re-propose alternatives unless asked.

Source of truth for backend: `stack/01-backend.md` (data/files/video/push) + `stack/02-ship.md` (hosting/CI/roadmap/costs). This file is the working contract for agents.

## Locked stack ($0 free tiers, no credit card)

| Layer | Pick | Notes |
|---|---|---|
| Auth + DB + Functions | Supabase, region `sa-east-1` | Postgres + RLS + RPC + Edge Functions. No custom API server. |
| Files (PDF/MP3/covers) | Supabase Storage via S3 protocol | `educador-public` (covers/avatars) + `educador-private` (PDF/audio). Presigned URLs only, R2-compatible layout for later swap. |
| Video | YouTube Unlisted only | Store `video_provider` (CHECK-gated `'youtube'`) + `video_id`, never MP4 bytes anywhere. Corporate networks must whitelist `youtube.com`. |
| PWA hosting | Cloudflare Pages, `educador.rgw.app` | Serves `build/web`, unlimited BW. Supabase hosts no HTML. |
| Push | FCM on Firebase Spark (messaging only) | Tokens stored in Supabase `fcm_tokens`. No Firestore/Storage/Hosting. |
| CI | GitHub Actions | lint/test/build web, Pages deploy, weekly `pg_dump` to private Storage bucket, daily keep-alive vs 7-day pause. |

Free ceilings (recheck dashboard, Sept 2026): Supabase 500MB DB / 1GB Storage / 5GB egress + 5GB cached / 50k MAU / 500k fn calls / 2 projects; R2 deferred (card required); Pages unlimited BW, 500 builds/mo, 20k files, 25MiB/file; FCM unlimited $0. Over Free = warn → restrict, no surprise charge. Domain $0 (uses existing `rgw.app`).

The stack is locked – do not improvise alternatives, ask instead.

## Repo map

* `lib/app/` – app shell, theme. `lib/core/router.dart` – role redirects + SPA routes (must keep Pages fallback `/* → /index.html`).
* `lib/data/models/models.dart` – `Role`, `User.companyId`, `Course/Module/Lesson` (lesson `kind: video/audio/pdf/quiz/reading`, `status: locked/inProgress/completed`).
* `lib/data/mock/mock_data.dart` – seed source for Supabase seed. Do not extend mocks; add real repos instead.
* `lib/data/repositories/repositories.dart` – **the seam**. All backend access goes here as `*Repository` + Riverpod providers. `features/` and `shared/widgets/` must never import `supabase_flutter`, `firebase_*`, or S3 SDKs directly.
* `lib/data/session/session_controller.dart` – session built from `profiles` row (`role`, `company_id`), not from mocks.
* `lib/features/{auth,gestor,company,employee}/screens.dart` – role UIs. `AddTrailScreen` content types map to `lessons.kind`; `Liberar para:` maps to `assignments(course_id,company_id)`.
* `stack/` – backend docs (2 files). `.github/workflows/` – CI (to be created per `stack/02-ship.md`).

## Patterns (must follow)

1. **Tenancy in DB, not client.** Every query filtered by `company_id`. RLS: gestor bypass, empresa `company_id = own`, funcionario `user_id = own`. Never trust client-side filtering. JWT claims `user_role`, `company_id` minted at login by the `custom_access_token_hook` Auth hook (top-level `role` is reserved by PostgREST – never rename back; employee invites go through a separate admin-only function).
2. **Files via presigned URLs (S3 protocol, R2-compatible).** Flutter holds no storage keys. Flow: `POST /functions/v1/storage-upload-url` (Supabase JWT) → PUT directly → save `file_key`/`cover_key` in Postgres. Reads via `storage-download-url` (1h) or public bucket URL. Buckets/keys/SDK calls must stay R2-compatible (endpoint + creds swap only; S3 SDK confined to Edge Functions). MIME allowlist: `pdf,mp3,webp,png,jpg` (no `mp4` – video is YouTube-only); upload cap 50MB (= Supabase Free per-file ceiling); covers client-resized to WebP.
3. **Video is YouTube-only.** `lessons(video_provider, video_id, file_key)` with `video_provider` CHECK-gated to `'youtube'`. Playback via `youtube_player_flutter`, save `position_sec` for resume. `AddTrailScreen` video = YouTube URL/ID field (no upload). Client-reported completion is accepted MVP risk (see `01-backend.md`).
4. **Reports as SQL, export client-side.** Use views/RPC (`completion_by_company`, `ranking(company_id)`, etc.), no BigQuery, no denormalized counter collections. CSV export in Flutter.
5. **Push via app-invoked function → FCM.** `firebase_messaging` token → upsert `fcm_tokens`. After the app inserts `assignments`/`certificates` it calls `push-on-assign` directly (no DB triggers; missed pushes acceptable, no resend UI in v1). Server sends via FCM HTTP v1 using service-account secret stored in Supabase secrets only.
6. **Env/secrets.** Public (baked at build): `SUPABASE_URL`, `SUPABASE_ANON_KEY` via `--dart-define`. Secret (never in app): Supabase service-role, Supabase S3 access keys, FCM service account → Supabase Function secrets / Actions secrets only.
7. **Free-tier discipline (egress budget).** PWA shell stays on Pages (zero Supabase egress). Covers/avatars via the public bucket (cached egress – keep WebP <200KB). PDFs/audio via short-lived signed URLs (metered egress). Video is YouTube-only (never Storage) to protect the 5GB quota. Paginate everything (`.range(0,49)`), no polling (Realtime only for ranking), cache signed URLs per session, no `bytea` columns, no event-log tables (activity from `lesson_progress.updated_at`; balances derived from `lessons.points`, no ledger table).
8. **PWA.** `flutter build web --pwa-strategy offline-first`; `index.html` no-cache, assets immutable; add new routes to Pages SPA fallback; register new web URLs in Supabase Auth URL config.
9. **MFA (when added).** TOTP only (free). Gate gestor writes with restrictive `aal2` policy; empresa/funcionario opt-in.

## Commands

```bash
flutter analyze
flutter test
flutter build web --release --pwa-strategy offline-first --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=VAPID_PUBLIC_KEY=...
npx wrangler pages deploy build/web --project-name=educador
```

Supabase changes: edit migrations, never hand-edit prod DB; seed from `mock_data.dart`; keep staging on 2nd free project.

## Workflow

* Commits follow Conventional Commits: `type(scope): short imperative summary` – e.g. `feat(rewards): add redeem flow`, `fix(auth): refresh session on 401`. Types: `feat/fix/docs/chore`; scope = area touched (`auth`, `reports`, `storage`, `ci`, `docs`).
* Branches off `main` as `feat/<short-slug>` or `fix/<short-slug>`.
* Language: user-facing strings in pt-BR; identifiers, comments, commits, docs in English.

## What to do / not do

* DO keep changes focused, reuse existing widgets/theme, run `analyze` + smallest relevant test.
* DO NOT put secrets, service-role keys, or S3/R2 credentials in Dart, docs, or committed workflows (use Actions/Supabase secrets).
* Ask one concise question when scope/security/cost is ambiguous; otherwise follow `stack/02-ship.md` build order.
