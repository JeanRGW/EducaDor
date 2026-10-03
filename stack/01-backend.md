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
  status text, all_companies bool default true, created_by uuid, created_at timestamptz default now());
modules(id uuid pk, course_id uuid references courses on delete cascade, title text, position int);
lessons(id uuid pk, module_id uuid references modules on delete cascade, title text,
  kind check (kind in ('video','audio','pdf','quiz','reading')),
  video_provider text default 'youtube' check (video_provider = 'youtube'),
  video_id text, file_key text, points int not null default 10,
  quiz_json jsonb, position int); -- points: per-task value set by gestor, no universal rule
assignments(course_id uuid, company_id uuid, released bool default true,
  company_enabled bool default true, primary key (course_id, company_id));
-- released = platform allowlist; company_enabled = company-wide employee switch
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
create policy content_read on courses for select using (
  is_gestor() or employee_can_access_course(id));
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
redemption. See the full SQL in `supabase/migrations/20260930000003_multi_context_content.sql`.

### Content access controls

`20260930000003_multi_context_content.sql` separates three gates for each trail:

1. Platform switch: `courses.status` is `released` or `paused`.
2. Platform audience: `courses.all_companies = true` includes current and future
   companies without inserting assignments for every company. Otherwise only
   `assignments.released = true` companies are eligible.
3. Company switch: `assignments.company_enabled` controls every employee in that
   company. A missing row defaults to enabled. It never overrides either platform gate.

Existing trails migrate to explicit-company mode, retaining their audience. New
trails default to all-company mode. Audience replacement changes only `released`,
so company pause preferences survive removals/re-additions and global pauses.
Paused content cannot be read or have progress inserted/updated by employees;
existing progress, balances and certificates remain intact. Reports use audience
eligibility, not pause state, so pausing does not erase historical completion.

`content_catalog` returns paginated metadata and company-scoped completion only,
not lessons, private keys or playback links. `set_course_platform_enabled` and
`set_course_audience` are gestor-only; `set_course_company_enabled` derives the
company from the active empresa context. The internal audience helper is not
callable by clients. `employee_can_access_course` checks the active employee
context and all gates, and is shared by read/progress RLS policies.

The live `Adicionar Trilha` form uses `publish_video_trail` to atomically create
the course, module, YouTube lesson, cover key, responsible professional and
audience. `p_cover_key` accepts only `covers/<id>.webp` keys minted by
`storage-upload-url`; `p_responsible_id` must reference a platform gestor
(`created_by` still records the publisher). PDF/audio uploads and quiz
authoring remain separate roadmap work; the form publishes video only and the
non-video type tiles are disabled. Failed cover uploads keep the draft on
screen instead of publishing without the cover.

With Supabase configured, employee Home/Modules and course outlines use
`CourseRepository` and normal RLS-protected reads instead of mock courses.
Blocked direct course URLs show an unavailable state. Playback/progress UI is
still separate roadmap work; the live outline does not simulate completion.

## Reports (SQL, export client-side)

Guarded views/RPC read via PostgREST, CSV export in Flutter. No BigQuery, no counter collections: `completion_by_company`, `completion_by_dept`, `engagement_monthly`, `popular_content`, `employee_completion(p_company uuid)`, `ranking(p_company uuid)` (company-scoped derived balances grouped per user, `LIMIT 20`). Managers see only their company's completion through guarded reports, not lesson contents.

### Company-manager data integration

`20261002000001_company_data.sql` adds `company_dashboard(p_company)` and
`company_employees(p_company, p_search, p_offset)`. Both require the signed Auth
session's active `empresa` role and require `p_company = own_company_id()`.
A global gestor grant does not bypass this context check; missing, revoked,
inactive-company or employee contexts are rejected. Only aggregate metadata is
returned, never lessons, video IDs or file keys. No new tables, event logs,
counters, polling or external services are introduced.

* Dashboard employee totals count accepted `funcionario` memberships exactly,
  including dual-role users once and excluding pending invitations. Counts in
  Profile use the same aggregate, not the first directory page.
* Active-course totals require platform release, audience eligibility and the
  company switch (missing assignments default to enabled). Completion and the
  top-two highlights retain the existing audience-only historical denominator,
  so pauses do not erase progress. Completion is weighted across all eligible
  employee/lesson opportunities; missing denominators stay null. Highlights
  consider all employees and use deterministic percentage/name/ID ordering.
* Certificate totals count retained issued records in that company, including
  former employees; pauses do not erase certificates. Issuing certificates is
  separate roadmap work, so a company without issued rows correctly shows zero.
* Participation zero-fills the trailing six São Paulo calendar months and counts
  distinct current employee identities with a latest progress update in each
  month, through now. It is not an immutable engagement history: later lesson
  updates move activity between months and removed employees are not counted.
* The employee directory uses literal case-insensitive name/department search
  **before** 50-row pagination, exact total/matching counts and stable lowercased
  name/user-ID ordering. Per-employee completion follows the same historical
  audience gate. Last activity is the maximum company-scoped progress timestamp
  through now, including previously available content, never another company's
  updates. Flutter formats it in the device's local timezone.
* Reports retain the guarded `completion_by_dept` view and current-completion
  wording. Leave status, regulatory thresholds, certificate-validity/renewal
  rules and unimplemented Profile workflows remain deferred; no arbitrary
  business rules are inferred. Exports, notifications and MFA remain deferred.

Verify `supabase/tests/company_data.sql` in an isolated database before an
operator-approved staging migration. Apply the migration **before** the Flutter
deployment; no Edge Function changes are required.

### Gestor data integration

`20261001000000_gestor_data.sql` adds the live platform queries. These RPCs
require the **active** `gestor` context, not just a platform grant or a legacy
JWT claim. `empresa`, `funcionario`, missing contexts and revoked grants cannot
use them. Flutter accesses them only through repository providers; no new API,
polling, analytics service, event table or denormalized counters are introduced.

* `gestor_dashboard`: total companies (including inactive companies), new
  companies since the start of the current São Paulo month, distinct registered
  identities (`profiles`, including provisioned invitations), and distinct users
  with a progress update in the trailing 30 days. Multi-company and dual-role
  identities count once. Completion is weighted across all eligible
  employee/company/lesson opportunities, including those without progress; it
  is **not** the mean of rounded company percentages. A missing denominator is
  `null`, not zero. Current memberships and audiences define eligibility;
  platform/company pauses and inactive companies do not erase completion.
* Growth contains six cumulative month-end counts of currently retained
  companies and identities. Companies use `companies.created_at`; identity
  dates are aggregated from `auth.users.created_at` inside the guarded RPC.
  Auth rows/credentials are never returned or granted to the client. The current
  month is month-to-date. These are not historical snapshots of memberships,
  deleted identities, or activation status. The chart uses a shared count scale
  for the company/user series.
* Recent activity combines actual company registration timestamps and the
  latest progress update per employee/company/lesson, newest first, capped at
  ten entries. Progress updates are not presented as module-completion events.
* `gestor_companies`: literal case-insensitive name search, server-side active
  filtering, deterministic name/ID ordering and 50-row pages. Filter counts
  include all search matches, independent of the selected active filter.
  Employee totals count accepted `funcionario` memberships, including people
  who also manage the company; pending invitations do not count.
* `gestor_completion`: 50-row pages of **current completion**, independent of
  the selected activity period. It reuses `completion_by_company` and includes
  companies with no eligible lessons/employees as `null` (no data).
* `gestor_activity_report`: the selected dates apply only to popular content
  and monthly engagement. Both endpoints of the date range are inclusive in
  `America/Sao_Paulo`; SQL uses `[start midnight, midnight after end)` and caps
  the range at 366 calendar days. Engagement counts distinct identities
  **globally per month**, never sums company-level distinct counts, and
  zero-fills missing months. Popular content groups by course ID (not title),
  with deterministic ordering and a top-ten limit. Its completion count is the
  number of currently completed employee/company/lesson records whose latest
  update falls within the range, **not** completed courses or certificates.
* `pending_invites_page` applies role/company filters before the 50-row cap and
  includes authorized company names, so invite labels do not depend on the
  visible company page. Existing scoped invitation/link security is unchanged.

**Current completion versus activity within a period:** `lesson_progress` is
current state, not a history table. Revisiting a lesson can move its `updated_at`
to a later period. Accordingly, activity charts and popular-content counts are
latest-update-based approximations, not immutable historical event counts.
Past completion rates, precise completion timestamps and interest/trend deltas
cannot be reconstructed reliably and are not fabricated. This distinction is
documented here rather than adding explanatory copy to the screens. The date
selector does not re-query or filter the current company-completion section.

Dashboard, Companies and Reports include loading, empty, retry and refresh
states. Gestor content routes reuse the real catalog and YouTube publisher
without mock fallbacks. CSV export, MFA, notifications and
non-video authoring remain deferred. Test the queries with
`supabase/tests/gestor_data.sql` on an isolated database; never apply fixtures or
new migrations to shared/staging databases without operator approval.

### Gestor lifecycle management

`20261002000000_gestor_management.sql` adds guarded company edits and
pause/reactivation, paginated platform/company gestor directories, scoped access
revocation, own-profile editing, and course metadata/lesson editing. Verify with
`supabase/tests/gestor_management.sql` on an isolated database first.

* Company detail is `/gestor/company/:id`. Pausing sets `companies.active=false`:
  both manager and employee contexts become unusable immediately in DB checks.
  Memberships, progress, certificates and company content preferences remain;
  reactivation restores eligibility. Company contact edits do not change any
  manager's Auth email or identity. The company list card shows "Convidar gestor
  da empresa" and "Editar" as matching outlined buttons in one row; there is no
  separate blue text button.
* `/gestor/gestores` and `/gestor/company/:id/gestores` list accepted grants with
  literal name/email search and 50-row pages. `revoke_gestor_access` removes only
  the chosen grant and its selected session contexts, plus any matching pending
  invitation. It never deletes the identity, employee memberships, other
  companies, learning records, or authorship. Both the platform and each company
  must retain at least one accepted gestor, even for inactive companies. Table
  locks serialize competing removals; the active caller is revalidated after
  waiting. Self-revocation clears the local context before session refresh so a
  failed network refresh cannot retain the old privileged UI context.
* Invitation acceptance is now `accept_membership_invite`, callable only by
  service-role inside `accept-invite`. The verified identity comes from the
  function caller, never the request body. Grant creation and invitation
  consumption are atomic and share the revocation lock order, preventing a
  previously fetched invitation from recreating a removed grant.
* `/gestor/perfil/edit` edits own name, phone, birth date and address. The RPC
  derives identity from `auth.uid()`; email and roles are never writable. The
  session reload updates name/initials throughout the app. If reload fails after
  saving, retry reload without duplicating the profile write. The form reuses the
  Gestor field labels above each input, the read-only access-email card, and the
  teal outlined date selector shared with the other management screens. Avatar,
  Auth email changes, password settings, notification preferences and MFA remain
  deferred.
* `/gestor/course/:id` edits title, description, cover and responsible, and lists
  lessons in stable module/lesson order with 50-row pages. Existing module/lesson
  titles and YouTube IDs can be edited. The "Liberar para" audience selector lives
  inside this screen: it loads the current audience through the guarded
  `gestor_course_audience` RPC and saves through the existing `set_course_audience`
  RPC, so company pause preferences survive audience changes. The platform catalog
  card keeps only the pause switch and an "Editar" button with the card's outlined
  teal treatment; there is no separate audience button on the card. Course editing
  updates rows in place, never recreates IDs or changes positions, points,
  progress, certificates, status or `company_enabled`. Replacing a video requires UI confirmation: existing
  completion and resume positions are intentionally retained, not interpreted
  as completion of newly substituted content. Renaming a module affects all its
  lessons. Previously credited responsible gestors remain valid when unchanged
  after grant revocation; new responsible selections require a current grant.
  Adding/deleting/reordering lessons, non-video body editing and drafts remain
  deferred.

Deployment order: apply the migration after operator approval, deploy the updated
`accept-invite` Edge Function, then ship Flutter. Do not deploy the function
before its server-only RPC exists. No staging migration or deployment is implicit
in these source changes.

## Edge Functions (Deno, 500k/mo free)

`invite-member` / `accept-invite` (manual link, verified recipient, service-role isolated in Functions) · `storage-upload-url` / `storage-download-url` (S3 SigV4 presign against the Storage endpoint) · `issue-certificate` (app-invoked after final lesson, idempotency key includes company + progress row; code `{prefix}-{6-char}`, `UNIQUE` + retry) · `push-on-assign` (FCM send, invoked by the app – no DB triggers anywhere). `custom_access_token_hook` remains installed as a passthrough so previously configured projects continue to issue JWTs.

## Files on Supabase Storage via S3 (presigned only, app holds no keys)

Buckets: `educador-public` (public covers/avatars) + `educador-private` (PDF/MP3/audio, signed GET 1h) + `educador-backups` (dumps only). Same names/layout as a future R2 setup. Dashboard per bucket: `file_size_limit` 50MB + matching MIME allowlist (defense-in-depth behind the function check). Keys: `courses/{courseId}/{uuid}-{slug}.pdf`, `covers/{courseId}.webp`, `avatars/{userId}.webp`.

Edge Functions use the S3 SDK (SigV4) against `https://<ref>.storage.supabase.co/storage/v1/s3`, so moving to R2 later = new endpoint + creds, zero Flutter changes. Server S3 keys stay in Supabase secrets (they bypass RLS); each function validates the caller JWT itself – one auth path, no session-token mode.

Upload: `POST /functions/v1/storage-upload-url {prefix, contentType, size}` → `{key, putUrl (15min)}` → Flutter PUTs directly → saves `file_key`/`cover_key`. Covers use `prefix: 'covers'` + `contentType: 'image/webp'` and are gestor-only; other prefixes are rejected. Read: `POST /functions/v1/storage-download-url {key}` → `{getUrl}`. Reject: missing JWT, non-gestor caller, wrong `company_id`, `size>50MB`, non-WebP cover content (no `mp4` – video is YouTube-only). Server secrets: `STORAGE_S3_ENDPOINT, STORAGE_S3_REGION, STORAGE_S3_ACCESS_KEY_ID, STORAGE_S3_SECRET_ACCESS_KEY, STORAGE_BUCKET_PRIVATE, STORAGE_BUCKET_PUBLIC`.

Flutter: covers → WebP 1200px max dimension, <200KB client-side (quality/downscale loop); chunked upload >5MB; cache `getUrl` per session; paginate `.range(0,49)`; public reads straight from the public bucket URL (cached egress), never through PostgREST. Files share the 1GB storage + 5GB egress quotas – keep them small, video stays on YouTube.

## Video

YouTube Unlisted only (`youtube_player_flutter`, store `video_id`); no Storage video – the 1GB quota forbids it. `AddTrailScreen` video type = YouTube URL/ID field, no file upload. Save `position_sec` for resume. Completion = client-reported ≥90% watched + quiz pass → `issue-certificate`. Accepted MVP risk: clients can forge completion and quiz answers ship inside `quiz_json` (client-graded); server-side recompute deferred. Corporate networks must whitelist `youtube.com`; blocked networks escalate to paid Stream/Bunny (see `02-ship.md` fallbacks).

## Push (FCM Spark, messaging only – no Firestore/Storage/Hosting)

Flutter `firebase_messaging getToken()` → upsert `fcm_tokens`. Direct send per stored token (no topics in v1). No DB triggers: after the app inserts `assignments`/`certificates` it invokes `push-on-assign` directly (idempotency key = row PK; missed pushes acceptable – notifications are optional, no resend UI in v1). Function sends via FCM HTTP v1 (service-account JSON in Supabase secrets). Unlimited $0; skip BigQuery analytics for MVP.
