# 03 – Multi-context onboarding

One Supabase Auth identity can be a platform `gestor`, an `empresa` manager,
and/or a `funcionario` in multiple companies. An `empresa` context has no
course access; the person must select `funcionario` to take courses. A context
selection applies to one signed Auth session, not all devices for that user.

## Current staging endpoints

* Supabase project ref: `lrlqmkamgncdgppyqnvu` (`sa-east-1`); public build inputs
  are in `config/staging.public.json`. The service-role key is **not** a build input.
* Cloudflare Pages project: `educador` in the `JeanRGW` account; production
  origin: `https://app.educador.rgw.app` (Pages alias:
  `https://educador-ayp.pages.dev`). Set Function secret `APP_ORIGIN` to the
  production origin without a trailing slash. Allow only trusted origins in
  `ALLOWED_APP_ORIGINS` when testing invites from the browser.
* Remote Auth Site URL is `https://app.educador.rgw.app/`. Allow its
  `/set-password` and `/invite/accept` callback paths (including the token
  query), plus localhost and the Pages alias when used for staging tests.
  Disable public signup and enable the passthrough Custom Access Token hook.

`supabase/config.toml` configures **local** Supabase development and uses
`http://localhost:8080` as its Site URL. `supabase db push` deploys migrations;
it does not push Auth settings or run the sample seed. Do **not** run
`supabase config push` against the linked staging project without reviewing
`supabase config diff` and the remote Auth URL first. Never run
`supabase db reset --linked` on shared data.

## Set up staging before inviting anyone

1. Apply migrations in order, including `20260923000000_multi_context.sql` and
   `20260925000000_service_role_grants.sql`.
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
4. Build Flutter with `--dart-define-from-file=config/staging.public.json`;
   deploy Pages with the `web/_redirects` fallback so invitation URLs survive
   refresh. The public file must never contain an admin credential.

From the repository root, an operator with access to the **staging** project
can link the CLI, review the pending migrations, and deploy the two implemented
invitation functions:

```bash
npx supabase login
npx supabase link --project-ref lrlqmkamgncdgppyqnvu
npx supabase db push --dry-run
# After confirming the linked project and migration list:
npx supabase db push
npx supabase secrets set --project-ref lrlqmkamgncdgppyqnvu \
  APP_ORIGIN=https://app.educador.rgw.app \
  ALLOWED_APP_ORIGINS=https://app.educador.rgw.app,https://educador-ayp.pages.dev,http://localhost:8080
npx supabase functions deploy invite-member --project-ref lrlqmkamgncdgppyqnvu
npx supabase functions deploy accept-invite --project-ref lrlqmkamgncdgppyqnvu
```

These commands do not run `supabase/seed.sql`; it contains throwaway sample
identities and must never be applied to production. The managed Supabase Auth
and service-role Function secrets are supplied by Supabase, not committed here.

## First platform gestor

From a trusted operator machine, copy the **legacy `service_role` key** from
Supabase Dashboard > Settings > API Keys. Enter it into a hidden shell prompt
by running the `read` command alone, pressing Enter after the key before
pasting the remaining commands:

```bash
read -rsp 'Supabase service-role key: ' SUPABASE_SERVICE_ROLE_KEY
SUPABASE_URL='https://lrlqmkamgncdgppyqnvu.supabase.co' \
APP_ORIGIN='https://app.educador.rgw.app' \
SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
python3 scripts/bootstrap_gestor.py first-gestor@example.com 'Full Name'
unset SUPABASE_SERVICE_ROLE_KEY
```

The script refuses to run when a platform gestor already exists. It creates
the Auth user, base profile and global grant before printing the one-time link.
Share that link privately. A retry can recover an unconfirmed Auth user with
no profile by generating a new sign-in link; inspect and repair any other
partial state in staging before retrying. Never add a public bootstrap button
or run `supabase/seed.sql` on production.

## Subsequent invitations

* Platform gestor: invite another platform gestor, or create a company with its
  first manager. An existing company's managers can also invite managers and
  employees **only for their active company**.
* `invite-member` checks the signed caller and their active DB context. It
  creates a one-hour, hashed invitation; a new Auth user gets a Supabase Auth
  invite link. An existing account receives a membership link to open after
  sign-in. The authorized inviter sees the link only once for private handoff.
  If it was lost, use **Gerar novo link** on the pending invitation: the old
  invitation token is invalidated, and only the newly generated link is shown.
  Platform gestores find pending invitations under Perfil (other platform
  gestores) or Empresas (company managers); company managers find theirs under
  Gestores or Funcionários.
  Company invitations must be regenerated for the existing company, not by
  creating another company. The first-gestor operator bootstrap is separate
  and cannot be rerun once its grant exists.
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
