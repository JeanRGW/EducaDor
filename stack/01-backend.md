# 01 – Backend (data/files/video/push)

Goal: ship EducaDor (Flutter, one identity with multiple `gestor`/`empresa`/`funcionario` contexts) on $0 free tiers, no credit card —
single Supabase project, region `sa-east-1` (LGPD); 2nd free project = staging.
Stack: Supabase Auth/Postgres/Functions/Storage (`sa-east-1`); Storage accessed via S3 protocol
with R2-compatible buckets/keys so a later R2 move is an endpoint swap. Video is YouTube Unlisted
only (corporate networks must whitelist `youtube.com`), FCM Spark for push. Ship details in `02-ship.md`.

## Tables (lean, target <100MB for 2k users)

```sql
companies(id uuid pk, name text, cnpj text unique, code_prefix text not null default 'EDU',
  responsible text, email text,
  phone text, address text, city text, state text, field text,
  active bool default true, created_at timestamptz default now());
profiles(id uuid pk references auth.users, full_name text, email text, avatar_key text,
  phone text, birth_date date, address text, needs_password bool);
platform_gestors(user_id uuid primary key references profiles);
company_memberships(user_id uuid references profiles, company_id uuid references companies,
  role text check (role in ('empresa','funcionario')), dept text, job_title text,
  primary key (user_id, company_id, role));
session_contexts(session_id uuid primary key, user_id uuid references profiles,
  role text, company_id uuid references companies); -- one active context per Auth session
membership_invites(id uuid primary key, email text, role text, company_id uuid,
  token_hash text unique, expires_at timestamptz); -- pending only; no plaintext links
courses(id uuid pk, title text, kind text, cover_key text, description text,
  status text, created_by uuid, created_at timestamptz default now());
modules(id uuid pk, course_id uuid references courses on delete cascade, title text, position int);
lessons(id uuid pk, module_id uuid references modules on delete cascade, title text,
  kind check (kind in ('video','audio','pdf','quiz','reading')),
  video_provider text default 'youtube' check (video_provider = 'youtube'),
  video_id text, file_key text, points int not null default 10,
  quiz_json jsonb, position int); -- points: per-task value set by gestor, no universal rule
assignments(course_id uuid, company_id uuid, released bool default true,
  primary key (course_id, company_id)); -- "Liberar para:"
lesson_progress(user_id uuid, company_id uuid, lesson_id uuid, status text, score int, position_sec int,
  updated_at timestamptz default now(), primary key (user_id, company_id, lesson_id));
certificates(id uuid pk, user_id uuid, company_id uuid, course_id uuid, code text unique, issued_at timestamptz default now(),
  unique(user_id, company_id, course_id)); -- one certificate per employee/company/course
-- code format: {companies.code_prefix}-{6-char Crockford base32}, e.g. GSM-K7Q2XA; UNIQUE + retry on collision
rewards(id uuid pk, title text, points_cost int, active bool default true);
redemptions(id uuid pk, user_id uuid, company_id uuid, reward_id uuid references rewards, created_at timestamptz default now());
fcm_tokens(user_id uuid, token text, platform text, updated_at timestamptz default now(),
  primary key (user_id, token));
```

No event-log table (activity = `lesson_progress.updated_at`). Quiz inline in `quiz_json`. Never store MP4/`bytea` bytes in Postgres (MP4s don't exist here – video is YouTube-only). Points are derived, never stored: balance = SUM(`lessons.points` over completed lessons) − SUM(`rewards.points_cost` over `redemptions`); no ledger table, no triggers.

## Auth + RLS

* `supabase_flutter`, one email/password login. If multiple contexts exist, show `/contexts` after login; otherwise auto-select. A company manager can invite managers/employees but must switch to an employee context to learn. The first platform gestor is created only by a trusted operator (`scripts/bootstrap_gestor.py`).
* `profiles` holds base identity only; `platform_gestors` and `company_memberships` grant contexts. `select_context()` validates a role/company against the DB and associates it with the signed JWT's `session_id`; `context_role()` and `own_company_id()` revalidate membership, company activity and active context for each request. The Auth hook no longer mints a single role/company claim. Sessions are built from the base profile + available/selected contexts. The PostgREST top-level JWT `role` remains reserved.
* New accounts get server-generated Auth invite links; existing accounts get a membership link. `invite-member`/`accept-invite` bind the link to the verified account email, grant the invited context only on acceptance, and never return a link to an unauthorized caller. Manual private handoff avoids Supabase's restricted built-in SMTP; see `03-onboarding.md`. Identity roles/tenants are never writable by app clients.
* Tenancy pattern on every tenant table (gestor global, empresa own-company management/reports only, funcionario assigned lessons and own progress in the active company). All points/certificates/redemptions include `company_id` to prevent cross-company mixing.

```sql
create policy progress_select on lesson_progress for select using (
  is_gestor() or (company_id = own_company_id() and
    (context_role() = 'empresa' or
      (context_role() = 'funcionario' and user_id = auth.uid()))));
```

* MFA (when added): TOTP only. Restrictive `aal2` policy on gestor writes; empresa/funcionario opt-in.

```sql
-- content tables: only employees in assigned companies can read lessons;
-- managers read completion via guarded SQL reports, never lesson content
create policy content_read on courses for select using (is_gestor() or
  (context_role() = 'funcionario' and exists (
  select 1 from assignments a where a.course_id = courses.id
  and a.company_id = own_company_id() and a.released)));
-- same shape for modules/lessons (via parent course) and companies (own row).
-- Global rewards are readable in employee/gestor contexts; per-company catalogs deferred.

-- storage.objects: public bucket world-readable, writes gestor-only; private bucket has NO
-- client policies – all access via signed URLs minted by functions (server S3 keys bypass RLS)
create policy pub_read on storage.objects for select using (bucket_id = 'educador-public');
create policy pub_write on storage.objects for insert
  with check (bucket_id = 'educador-public' and is_gestor());

```

`redeem_reward` requires an employee context, locks the user/company balance,
calculates earned/spent points within that company, and inserts a company-scoped
redemption. See the full SQL in `supabase/migrations/20260923000000_multi_context.sql`.

## Reports (SQL, export client-side)

Guarded views/RPC read via PostgREST, CSV export in Flutter. No BigQuery, no counter collections: `completion_by_company`, `completion_by_dept`, `engagement_monthly`, `popular_content`, `employee_completion(p_company uuid)`, `ranking(p_company uuid)` (company-scoped derived balances grouped per user, `LIMIT 20`). Managers see only their company's completion through guarded reports, not lesson contents.

## Edge Functions (Deno, 500k/mo free)

`invite-member` / `accept-invite` (manual link, verified recipient, service-role isolated in Functions) · `storage-upload-url` / `storage-download-url` (S3 SigV4 presign against the Storage endpoint) · `issue-certificate` (app-invoked after final lesson, idempotency key includes company + progress row; code `{prefix}-{6-char}`, `UNIQUE` + retry) · `push-on-assign` (FCM send, invoked by the app – no DB triggers anywhere). `custom_access_token_hook` remains installed as a passthrough so previously configured projects continue to issue JWTs.

## Files on Supabase Storage via S3 (presigned only, app holds no keys)

Buckets: `educador-public` (public covers/avatars) + `educador-private` (PDF/MP3/audio, signed GET 1h) + `educador-backups` (dumps only). Same names/layout as a future R2 setup. Dashboard per bucket: `file_size_limit` 50MB + matching MIME allowlist (defense-in-depth behind the function check). Keys: `courses/{courseId}/{uuid}-{slug}.pdf`, `covers/{courseId}.webp`, `avatars/{userId}.webp`.

Edge Functions use the S3 SDK (SigV4) against `https://<ref>.storage.supabase.co/storage/v1/s3`, so moving to R2 later = new endpoint + creds, zero Flutter changes. Server S3 keys stay in Supabase secrets (they bypass RLS); each function validates the caller JWT itself – one auth path, no session-token mode.

Upload: `POST /functions/v1/storage-upload-url {prefix, filename, contentType, size}` → `{key, putUrl (15min)}` → Flutter PUTs directly → saves `file_key`/`cover_key`. Read: `POST /functions/v1/storage-download-url {key}` → `{getUrl}`. Reject: missing JWT, wrong `company_id`, `size>50MB`, mime outside `pdf,mp3,webp,png,jpg` (no `mp4` – video is YouTube-only). Server secrets: `STORAGE_S3_ENDPOINT, STORAGE_S3_ACCESS_KEY_ID, STORAGE_S3_SECRET_ACCESS_KEY, STORAGE_BUCKET_PRIVATE, STORAGE_BUCKET_PUBLIC`.

Flutter: covers → WebP 800px <200KB client-side; chunked upload >5MB; cache `getUrl` per session; paginate `.range(0,49)`; public reads straight from the public bucket URL (cached egress), never through PostgREST. Files share the 1GB storage + 5GB egress quotas – keep them small, video stays on YouTube.

## Video

YouTube Unlisted only (`youtube_player_flutter`, store `video_id`); no Storage video – the 1GB quota forbids it. `AddTrailScreen` video type = YouTube URL/ID field, no file upload. Save `position_sec` for resume. Completion = client-reported ≥90% watched + quiz pass → `issue-certificate`. Accepted MVP risk: clients can forge completion and quiz answers ship inside `quiz_json` (client-graded); server-side recompute deferred. Corporate networks must whitelist `youtube.com`; blocked networks escalate to paid Stream/Bunny (see `02-ship.md` fallbacks).

## Push (FCM Spark, messaging only – no Firestore/Storage/Hosting)

Flutter `firebase_messaging getToken()` → upsert `fcm_tokens`. Direct send per stored token (no topics in v1). No DB triggers: after the app inserts `assignments`/`certificates` it invokes `push-on-assign` directly (idempotency key = row PK; missed pushes acceptable – notifications are optional, no resend UI in v1). Function sends via FCM HTTP v1 (service-account JSON in Supabase secrets). Unlimited $0; skip BigQuery analytics for MVP.
