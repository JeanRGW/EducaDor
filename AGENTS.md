# AGENTS.md – EducaDor

Flutter training platform. One Auth user may have the global `gestor` role and any number of company memberships (`empresa` manager and/or `funcionario` employee, including both in one company). The user selects a role/company context after login; the only available context is selected automatically. An `empresa` context monitors completion and manages invites but cannot learn; the same person must switch to a `funcionario` context to take courses. UI mocks exist in `lib/features/`; backend plan is decided – follow it, do not re-propose alternatives unless asked.

Source of truth for backend: `stack/01-backend.md` (data/files/video/push) + `stack/02-ship.md` (hosting/CI/roadmap/costs). This file is the working contract for agents.

## Locked stack ($0 free tiers, no credit card)

| Layer | Pick | Notes |
|---|---|---|
| Auth + DB + Functions | Supabase, region `sa-east-1` | Postgres + RLS + RPC + Edge Functions. No custom API server. |
| Files (PDF/MP3/covers) | Supabase Storage via S3 protocol | `educador-public` (covers/avatars) + `educador-private` (PDF/audio). Presigned URLs only, R2-compatible layout for later swap. |
| Video | YouTube Unlisted only | Store `video_provider` (CHECK-gated `'youtube'`) + `video_id`, never MP4 bytes anywhere. Corporate networks must whitelist `youtube.com`. |
| PWA hosting | Cloudflare Pages, `app.educador.rgw.app` | Serves `build/web`, unlimited BW. Supabase hosts no HTML. |
| Push | FCM on Firebase Spark (messaging only) | Tokens stored in Supabase `fcm_tokens`. No Firestore/Storage/Hosting. |
| CI | GitHub Actions | lint/test/build web, Pages deploy, weekly `pg_dump` to private Storage bucket, daily keep-alive vs 7-day pause. |

Free ceilings (recheck dashboard, Sept 2026): Supabase 500MB DB / 1GB Storage / 5GB egress + 5GB cached / 50k MAU / 500k fn calls / 2 projects; R2 deferred (card required); Pages unlimited BW, 500 builds/mo, 20k files, 25MiB/file; FCM unlimited $0. Over Free = warn → restrict, no surprise charge. Domain $0 (uses existing `rgw.app`).

The stack is locked – do not improvise alternatives, ask instead.

## Repo map

* `lib/app/` – app shell, theme. `lib/core/router.dart` – role redirects + SPA routes (must keep Pages fallback `/* → /index.html`).
* `lib/data/models/models.dart` – base `User`, `AccessContext(role, companyId)`, `Course/Module/Lesson` (lesson `kind: video/audio/pdf/quiz/reading`, `status: locked/inProgress/completed`).
* `lib/data/mock/mock_data.dart` – seed source for Supabase seed. Do not extend mocks; add real repos instead.
* `lib/data/repositories/repositories.dart` – **the seam**. All backend access goes here as `*Repository` + Riverpod providers. `features/` and `shared/widgets/` must never import `supabase_flutter`, `firebase_*`, or S3 SDKs directly.
* `lib/data/session/session_controller.dart` – session built from base `profiles` plus `available_contexts()`/`selected_context()`; active context is checked by DB per Auth session.
* `lib/features/{auth,gestor,company,employee}/screens.dart` – role UIs. `lib/features/content/` – live catalog, audience/professional pickers, cover processing and YouTube publishing. `Liberar para:` uses `courses.all_companies` or explicit `assignments(course_id,company_id,released)`; company manager management is under Profile, not a main tab.
* `supabase/schemas/` – editable database source of truth (tables, functions, views, policies and grants). `supabase/migrations/` – generated deployment history plus explicit DML provisioning. `stack/07-database.md` – declarative workflow and reset runbook.
* `stack/` – backend, shipping, onboarding docs. `scripts/bootstrap_gestor.py` – trusted first-gestor bootstrap. `.github/workflows/database.yml` – isolated schema drift and SQL regression checks; other CI follows `stack/02-ship.md`.

## Patterns (must follow)

1. **Tenancy and active role in DB, not client.** `profiles` is identity only; `platform_gestors` and `company_memberships(user_id, company_id, role)` grant independent contexts. `select_context()` validates membership and stores the choice against the signed Auth JWT's `session_id`; `context_role()`/`own_company_id()` validate it on each DB operation. RLS: gestor global, empresa own-company management/reports only (no lesson reads or progress writes), funcionario assigned content and own progress in the active company. No single-role `user_role`/`company_id` JWT claims. Never trust client-side filtering. `invite-member`/`accept-invite` are admin-only Edge Functions separate from the Auth hook.
2. **Files via presigned URLs (S3 protocol, R2-compatible).** Flutter holds no storage keys. Flow: `POST /functions/v1/storage-upload-url` (Supabase JWT) → PUT directly → save `file_key`/`cover_key` in Postgres. Reads via `storage-download-url` (1h) or public bucket URL. Buckets/keys/SDK calls must stay R2-compatible (endpoint + creds swap only; S3 SDK confined to Edge Functions). MIME allowlist: `pdf,mp3,gif,webp,png,jpg` (GIF approved for animated lessons; no `mp4` – video is YouTube-only); upload cap 50MB (= Supabase Free per-file ceiling); covers client-resized to WebP. Lesson files, including GIFs and image sequences, use the private bucket and `lessons/` keys. Download signing checks lesson RLS and batches all frames in one function call.
3. **Video is YouTube-only.** `lessons(video_provider, video_id, file_key)` with `video_provider` CHECK-gated to `'youtube'`. Playback via `youtube_player_flutter`, save `position_sec` for resume. Video lessons use a YouTube URL/ID field (no upload). Create a course first, then add modules and typed lessons; see `stack/03-content.md`. Client-reported completion is accepted MVP risk (see `01-backend.md`).
4. **Reports as SQL, export client-side.** Use guarded views/RPC (`completion_by_company`, `employee_completion`, `ranking(company_id)`, etc.); all progress/certificates/redemptions and derived balances are company-scoped. No BigQuery or denormalized counter collections. CSV export in Flutter.
5. **Planned push via app-invoked function → FCM.** After a successful course availability mutation or certificate issuance, the app invokes `push-on-assign` with a typed event, not arbitrary recipients or message text. The server resolves authorized recipients and all three course access gates, bounds best-effort sends and uses FCM HTTP v1 with a server-only service account. No DB triggers, inbox, topics, reminders or resend; missed pushes are acceptable. Token lifecycle and account preference require explicit permission and privacy protections. See `stack/13-security-push-round.md` for status and integration gates.
6. **Env/secrets.** Public (baked at build): `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the publishable key) in `config/staging.public.json` via `--dart-define-from-file`. Secret (never in app): Supabase service-role, Supabase S3 access keys, FCM service account → Supabase Function secrets / Actions secrets only.
7. **Free-tier discipline (egress budget).** PWA shell stays on Pages (zero Supabase egress). Covers/avatars via the public bucket (cached egress – keep WebP <200KB). PDFs/audio via short-lived signed URLs (metered egress). Video is YouTube-only (never Storage) to protect the 5GB quota. Paginate everything (`.range(0,49)`), no polling (Realtime only for ranking), cache signed URLs per session, no `bytea` columns, no event-log tables (activity from `lesson_progress.updated_at`; balances derived from `lessons.points`, no ledger table). `membership_invites` and `session_contexts` store current authorization state, not events.
8. **PWA.** After `flutter build web --pwa-strategy offline-first`, run `node scripts/generate-shell-worker.mjs build/web` before any publication: Flutter's generated worker alone does not cache the shell. The custom worker caches public build artifacts only, never private/Auth/API responses or bearer URLs; see `stack/12-pwa-reliability.md`. Entry points use no-cache; unfingerprinted assets revalidate; Pages SPA fallback covers `/contexts`, `/invite/accept`, `/set-password`; register web URLs in Supabase Auth URL config. Manual invite links are bearer credentials: never log/store plaintext, only give to authorized inviters for private handoff. First gestor bootstrap is operator-only, never a public signup page.
9. **Planned MFA.** TOTP enrollment is optional for every account, including gestores. Enrolled accounts must complete an `aal2` challenge and server-side enforcement; unenrolled accounts are not forced to enroll. No SMS or custom recovery bypass. Lost-factor recovery requires a documented operator procedure; see `stack/13-security-push-round.md`.
10. **Content access has three independent gates.** `courses.status = 'released'` is the platform-wide switch; `courses.all_companies` includes future companies or `assignments.released` defines the allowlist; `assignments.company_enabled` is the company's own pause preference (default true, including when no assignment row exists). Managers use guarded metadata/mutation RPCs, never lesson reads. Course/module/lesson reads and progress writes require all three gates. Pauses preserve progress and company preferences; audience changes never reset `company_enabled`. Existing catalogs retain their explicit assignments when migrating; new trails default to all companies.

## Commands

```bash
flutter analyze
flutter test
bash scripts/db.sh generate meaningful_change_name
bash scripts/db.sh reset
bash scripts/db.sh check
bash scripts/db.sh test
flutter build web --release --pwa-strategy offline-first --dart-define-from-file=config/staging.public.json
node scripts/generate-shell-worker.mjs build/web
node --test scripts/pwa/*.test.mjs
# Operator-approved deployment only:
CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 npx wrangler pages deploy build/web --project-name=educador --branch=main
```

Supabase changes: edit `supabase/schemas/`, then generate and review migrations with `bash scripts/db.sh generate <name>` (pinned Supabase CLI 2.122.0, pg-delta). Never use `db diff` for declarative changes or edit the live schema in Studio/SQL editor. Do not hand-edit generated migrations or rewrite deployed history. DML (including Storage buckets) belongs in an explicit migration or opt-in seed, never in declarative SQL. The pre-production history was replaced once with a fresh baseline; future changes roll forward. Remote resets require explicit operator approval. Seed demo data only when its Auth users exist; keep staging on 2nd free project. `supabase/config.toml` is local-only (localhost Auth Site URL); never push it to staging without reviewing the remote config diff.

## Workflow

* Commits follow Conventional Commits: `type(scope): short imperative summary` – e.g. `feat(rewards): add redeem flow`, `fix(auth): refresh session on 401`. Types: `feat/fix/docs/chore`; scope = area touched (`auth`, `reports`, `storage`, `ci`, `docs`).
* Branches off `main` as `feat/<short-slug>` or `fix/<short-slug>`.
* Language: user-facing strings in pt-BR; identifiers, comments, commits, docs in English.

## What to do / not do

* DO keep changes focused, reuse existing widgets/theme, run `analyze` + smallest relevant test.
* DO NOT put secrets, service-role keys, or S3/R2 credentials in Dart, docs, or committed workflows (use Actions/Supabase secrets).
* Ask one concise question when scope/security/cost is ambiguous; otherwise follow `stack/02-ship.md` build order.
