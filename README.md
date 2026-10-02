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
Dashboard, Companies, Content and Reports use live repositories; some company
and employee screens still use mocks. CSV export remains deferred. Report
metric definitions and current-completion/activity-period semantics are
documented in [the backend contract](stack/01-backend.md#gestor-data-integration).
Gestor lifecycle routes support company edits/pause, manager grant revocation,
own-profile edits and progress-preserving course/video edits. Deployment order
and boundaries are documented under
[Gestor lifecycle management](stack/01-backend.md#gestor-lifecycle-management).

## Local setup

Read [the onboarding runbook](stack/03-onboarding.md) for Supabase staging,
migrations, Auth URLs, Edge Function secrets and first-gestor provisioning.
Backend contracts and shipping notes are in [stack/01-backend.md](stack/01-backend.md)
and [stack/02-ship.md](stack/02-ship.md).

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

```bash
flutter build web --release --pwa-strategy offline-first \
  --dart-define-from-file=config/staging.public.json
CLOUDFLARE_ACCOUNT_ID=785b73d97c037eb906aae65de518cad6 \
  npx wrangler pages deploy build/web --project-name=educador --branch=main
```

Log in with `npx wrangler login --device` first if needed. The `web/_redirects`
rule serves direct `/invite/accept`, `/contexts` and `/set-password` paths.
Without public defines the welcome screen renders, but sign-in and invitations
cannot use staging. The Android release build still needs Internet permission
and a real signing key before store distribution.

Never put a service-role key, database password, Cloudflare token or invitation
link in the public JSON file or the repository. `supabase/config.toml` configures
**local** Supabase development (localhost Auth URL); do not run
`supabase config push` against staging without reviewing the differences.

`supabase/tests/multi_context.sql`, `supabase/tests/content_access.sql`,
`supabase/tests/gestor_data.sql` and `supabase/tests/gestor_management.sql` check
selected-session tenancy, content access, platform aggregates and guarded
lifecycle operations on an **isolated** PostgreSQL database after applying
migrations. They create fixtures inside transactions and roll them back.
