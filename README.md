# EducaDOR

Flutter training platform with one account and selectable platform/company roles.
Onboarding is invitation-only. A company manager can monitor completion and
invite colleagues; they must switch to an employee context to take courses.

## Local setup

Read [the onboarding runbook](stack/03-onboarding.md) for Supabase staging,
migrations, Auth URLs, Edge Function secrets and first-gestor provisioning.
Backend contracts and shipping notes are in [stack/01-backend.md](stack/01-backend.md)
and [stack/02-ship.md](stack/02-ship.md).

```bash
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
flutter analyze
flutter test
```

Build the Pages PWA with the same public defines and
`flutter build web --release --pwa-strategy offline-first`. The `web/_redirects`
rule serves direct `/invite/accept`, `/contexts`, and `/set-password` paths.
Without Supabase defines, the welcome screen renders, but sign-in and
invitations require a configured staging project.

`supabase/tests/multi_context.sql` checks selected-session tenancy and role
restrictions on an **isolated** PostgreSQL database after applying migrations.
