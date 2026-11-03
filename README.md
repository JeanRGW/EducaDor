# EducaDOR

Flutter training platform with one account and selectable platform/company roles.
Onboarding is invitation-only. A company manager can monitor completion and
invite colleagues; they must switch to an employee context to take courses.

## Staging

The staging app runs at https://app.educador.rgw.app (Cloudflare Pages project
`educador`); Supabase is in `sa-east-1`. The repository's
[`config/staging.public.json`](config/staging.public.json) contains only the
project URL and publishable client key. `SUPABASE_ANON_KEY` is the existing Dart
define name, even though its value is a publishable key. These values are
already visible in any web build; row-level security protects the data.

Authentication, context selection and invitations use Supabase. Gestor
Dashboard, Companies, Content and Reports, and all company-manager screens,
use live repositories. Employee screens now cover live learning,
YouTube playback/resume, progress, certificates, rewards/redemption and profile
editing; see [Employee features](stack/06-employee-features.md) for deployment
requirements and deferred boundaries. CSV export remains deferred. Report
metric definitions and current-completion/activity-period semantics are
documented in [the backend contract](stack/01-backend.md#gestor-data-integration).
Gestor lifecycle routes support company edits/pause, manager grant revocation,
own-profile edits and progress-preserving course/video edits. Deployment order
and boundaries are documented under
[Gestor lifecycle management](stack/01-backend.md#gestor-lifecycle-management).

Company-manager layouts follow the `ca-*.png` prototypes. Screen mapping,
existing-data limits and intentional differences are documented in
[Company screen parity](stack/05-company-screen-parity.md).

## Local setup

Read [the onboarding runbook](stack/03-onboarding.md) for Supabase staging,
Auth URLs, Edge Function secrets and first-gestor provisioning. Database definitions
live in [`supabase/schemas/`](supabase/schemas/); see the
[declarative database workflow](stack/07-database.md) for generation, testing and deployment.
Backend contracts and shipping notes are in [stack/01-backend.md](stack/01-backend.md)
and [stack/02-ship.md](stack/02-ship.md).

The [implementation gap review](stack/08-implementation-roadmap.md) distinguishes
assigned workstreams, remaining prerequisites, intentional deferrals and features
already implemented. Assignment does not imply a merged or deployed feature.

```bash
flutter pub get
flutter run -d chrome --web-port=8080 \
  --dart-define-from-file=config/staging.public.json
# With an Android device or emulator running, find its ID first:
flutter devices
flutter run -d YOUR_ANDROID_DEVICE_ID \
  --dart-define-from-file=config/staging.public.json
flutter analyze
flutter test
```

Replace `YOUR_ANDROID_DEVICE_ID` with the ID reported by `flutter devices` on
your machine; emulator IDs are local and may differ between developers.

## Manual staging deploy

Deployment requires explicit operator approval; generating the artifact does not authorize publication.

```bash
flutter build web --release --pwa-strategy offline-first \
  --dart-define-from-file=config/staging.public.json
node scripts/generate-shell-worker.mjs build/web
node --test scripts/pwa/*.test.mjs
CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 \
  npx wrangler pages deploy build/web --project-name=educador --branch=main
```

Requires Node.js 24. Generate the static-shell worker after every Flutter build,
before publishing; Flutter's generated worker alone does not provide offline caching.
See [PWA reliability](stack/12-pwa-reliability.md) for the cache boundary and limitations.

Log in with `npx wrangler login --device` first if needed. The `web/_redirects`
rule serves direct `/invite/accept`, `/contexts` and `/set-password` paths.
Without public defines the welcome screen renders, but sign-in and invitations
cannot use staging. The Android release build still needs Internet permission
and a real signing key before store distribution.

Never put a service-role key, database password, Cloudflare token or invitation
link in the public JSON file or the repository. `supabase/config.toml` configures
**local** Supabase development (localhost Auth URL); do not run
`supabase config push` against staging without reviewing the differences.

## Database development

Requires Node.js 24 and Docker. Commands pin Supabase CLI 2.122.0 and use pg-delta.

```bash
npx --yes supabase@2.122.0 db start
# Edit SQL definitions under supabase/schemas/, then:
bash scripts/db.sh generate meaningful_change_name
# Review the generated migration before applying it locally:
bash scripts/db.sh reset
bash scripts/db.sh check
bash scripts/db.sh test
node --test supabase/tests/invite_member.test.mjs
```

`reset` is local-only and deletes local data. `check` fails on declarative/migration
drift. SQL tests create transactional fixtures and roll them back. CI repeats this
workflow without credentials or access to staging. Storage buckets are provisioned
by a separate DML migration; the sample `supabase/seed.sql` is never automatic.
