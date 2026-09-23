# 03 – Multi-context onboarding

One Supabase Auth identity can be a platform `gestor`, an `empresa` manager,
and/or a `funcionario` in multiple companies. An `empresa` context has no
course access; the person must select `funcionario` to take courses. A context
selection applies to one signed Auth session, not all devices for that user.

## Set up staging before inviting anyone

1. Apply migrations in order, including `20260923000000_multi_context.sql`.
   The later migration moves legacy roles to `platform_gestors` and
   `company_memberships`, and backfills progress/certificates/redemptions with
   the user's former company. It aborts if a legacy learning record has no
   company, rather than assigning it arbitrarily.
2. Configure Supabase Auth Site URL to your app origin and allow the exact
   `/invite/accept` and `/set-password` paths (including query parameters),
   localhost and any staging preview origins used for testing. Keep the
   existing Custom Access Token hook enabled; the current function is a
   passthrough. Confirm that admin-generated invite links work when public
   self-signup is disabled in the Auth dashboard.
3. Deploy `invite-member` and `accept-invite` with JWT verification enabled.
   Set Supabase Function secret `APP_ORIGIN` to the app origin and optionally
   `ALLOWED_APP_ORIGINS` to a comma-separated list of trusted web origins.
   Supabase's service-role secret is available to Edge Functions only. Never
   bundle it in Flutter or expose the Admin API to a client.
4. Build Flutter with `SUPABASE_URL` and `SUPABASE_ANON_KEY`; deploy Pages with
   the `web/_redirects` fallback so invitation URLs survive refresh.

## First platform gestor

From a trusted operator machine with `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY` and `APP_ORIGIN` set in the environment:

```bash
python3 scripts/bootstrap_gestor.py first-gestor@example.com 'Full Name'
```

The script refuses to run when a platform gestor already exists. It creates
the Auth user, base profile and global grant before printing the one-time link.
Share that link privately. If any step fails, inspect and repair the partial
Auth/profile record in staging before retrying. Never add a public bootstrap
button or run `supabase/seed.sql` on production.

## Subsequent invitations

* Platform gestor: invite another platform gestor, or create a company with its
  first manager. An existing company's managers can also invite managers and
  employees **only for their active company**.
* `invite-member` checks the signed caller and their active DB context. It
  creates a one-hour, hashed invitation; a new Auth user gets a Supabase Auth
  invite link. An existing account receives a membership link to open after
  sign-in. The authorized inviter sees the link only once for private handoff.
* The recipient's verified Auth email must match the invitation. Acceptance
  adds a grant to the same account; it never creates a second account or
  accepts the role/company from the browser. New users set a password before
  using their profiles. If a link expires, create a fresh invitation.
* Supabase's default email sender is limited to project-team addresses and is
  unsuitable for these invitations. Until custom SMTP is configured, the
  platform does not promise email recovery: a trusted operator must verify the
  person's identity before generating a manual Supabase recovery link.

## Staging checks

Run `flutter analyze`, `flutter test` and
`supabase/tests/multi_context.sql` on an isolated local database after applying
the migrations. Verify first-gestor bootstrap, a new company manager, an
existing user's second company, both roles in the same company, expired or
wrong-email links, and direct URL attempts to access employee lessons as a
manager. Keep Auth links and service credentials out of logs and commits.
