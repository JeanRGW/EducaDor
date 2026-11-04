# Security and push: combined integration

## Status

Combined integration branch `feat/security-push-integration`, based on `main`
`62d6460`, merges the completed source branches in this order:

| Source | Head merged | Pull request |
| --- | --- | --- |
| `docs/security-push-round` | `aad3e2d` | #17 |
| `feat/optional-totp` | `d592a13` | #19 |
| `feat/fcm-backend` | `768f46e` | #18 |
| `feat/fcm-client` | `f0f88a8` | #20 |

The integration branch is a review vehicle, not a release. It is not merged into
`main`, not deployed and it changes nothing hosted. Feature history repeats inside
the merge until the source PRs land; that is expected and resolves once the
dependencies merge in order. Source PRs remain independently reviewable.

**Status: validated on the final client head, ready for review.** The source
branches are complete and their own reviews are closed. Client `f0f88a8` was
merged here with no conflicts, and the combined SQL, Node, Deno, Flutter, release
build, shell worker, PWA and browser checks below all pass on that tree. This is
still an integration review vehicle: it is not merged into `main`, not deployed and
it changes nothing hosted. Dependencies are PRs #17, #18, #19 and #20; the
integration fix commits are additional to those branches.

## Added integration fix

Independent branches left one trust-boundary gap: the new
`notification_preferences` table exposed a direct own-row `SELECT` policy without
the MFA restrictive guard that already protected `profiles`, memberships, gestor
rows and `fcm_tokens`. An enrolled account at `aal1` could therefore read its push
preference.

The integration branch adds only that missing policy in the declarative schema
(`supabase/schemas/public/mfa_policies.sql`) and generates
`supabase/migrations/20261104012732_guard_notification_preferences_mfa.sql` with
the pinned CLI (`supabase@2.122.0`). No author implementation was rewritten.

Resulting boundary:

- `authenticated` own-row reads of `notification_preferences` require
  `mfa_access_allowed()`, so enrolled `aal1` sessions read nothing.
- `register_fcm_token`, `set_push_enabled` and `unregister_fcm_token` already
  `PERFORM context_role()` and therefore inherit the same central guard.
- `unregister_fcm_token` stays identity-only for cleanup: it does not require an
  active company context, but the MFA guard still applies to the subject.
- Unenrolled sessions and every non-`authenticated` role are unchanged.

## Client integration glue

`NotificationController` derived the active push context from
`session.active` alone. A combined session can be `needsMfa` or `needsPassword`
while still carrying stale context data, which would have attempted token
registration before the account finished the TOTP challenge. The branch extracts
`notificationContextKey()`, which returns `null` for a missing session, an MFA
challenge, a pending password, or no active context. Registration and refresh are
therefore suppressed until the session is fully authorized; the database remains
the final enforcement point.

The MFA security row (`/account/security`) and the notification settings tile live
together in the shared profile, and the dashboard bell still opens the notification
sheet. With Firebase configuration absent the tile reports the honest
`unconfigured` state and the switch stays disabled.

## Verification performed

Isolated local project `EducaDorRound2` on `+6000` ports, own container; the shared
`supabase_db_EducaDor` container and hardcoded `scripts/db.sh test` were not used.

SQL, drift, Node, Deno, Flutter, build, worker and browser checks below were all
rerun on the merged `f0f88a8` client head.

- `supabase db start`, `bash scripts/db.sh reset` from migrations: all 17
  migrations apply, including the new guard.
- `bash scripts/db.sh check`: `No schema changes found` (declarative/migration
  parity).
- All 15 files under `supabase/tests/*.sql` pass against the isolated container,
  including `optional_totp.sql` (now also asserts enrolled `aal1` cannot read
  preferences, register, change or unregister tokens; `aal2` with and without an
  active context works), `fcm_registration.sql`, `push_delivery.sql`,
  `content_access.sql` and `schema_contract.sql`.
- Release gate, audience, company enablement and certificate-creation coverage come
  from `push_delivery.sql` on the merged schema.
- `node --test supabase/tests/invite_member.test.mjs` (20 tests) and
  `node --test scripts/pwa/*.test.mjs` (10 tests) pass.
- Deno 2.9.6, matching the database workflow pin and the storage/SDK coverage:
  `deno test supabase/functions/ --ignore=supabase/functions/storage-upload-url/signing_test.ts`
  passes 12 tests; the offline signing test runs separately with its documented
  env/sys allowlist and passes 1 test. `deno check --frozen --config ...` passes for
  the storage upload/download entry points plus their tests, and `deno check`
  passes for `push-on-assign`, `issue-certificate`, `invite-member` and
  `accept-invite`.
- Verified-caller review: `_shared/invites.ts#caller()` calls the caller-context
  `require_mfa_if_enrolled` RPC before returning the service-role client. The real
  entry points (`push-on-assign`, `issue-certificate`, `invite-member`,
  `accept-invite`, `_shared/storage_runtime.ts`) all call `caller()`; the mocked
  sender test does not stand in for that inspection.
- Flutter under the shared lock with `--concurrency=2`: `flutter analyze`, full
  `flutter test` (291 tests), release web build with `--dart-define-from-file`, and
  shell worker generation pass; all 10 PWA worker tests pass, including the
  SDK-notification-displays-once and earlier-safe-click-handler test. Widget tests
  assert the configuration-off tile text and that the push switch is disabled.
- Browser smoke on the final release build, served locally, no hosted mutation and
  no Firebase configuration: welcome and login render, `/account/security` and
  `/mfa` redirect to `/login` for an unauthenticated visitor, the shell worker
  registers, the only cache is the public static shell (100 entries) with no
  auth/API/token/private-route entries, and no Firebase/FCM network requests occur.

## Not covered / release gates

- No real Firebase project, web VAPID key, Android config or FCM service account;
  real delivery, permission UX and Android device behavior are operator gates.
- No hosted Supabase change; the new migration is not pushed.
- Lost-factor recovery, hosted TOTP configuration and MFA behavior of the hosted
  Auth service remain operator verification.
- The client branch's Android debug build was verified by its author and was not
  repeated here because the integration changes do not touch native code.
- Token cleanup is best effort. A network failure or rejected credential during
  cleanup can leave a registration row, and a failed provider-token deletion cannot
  guarantee instant revocation of an already issued token. Real delivery, real
  devices and those failure paths remain operator/device verification.

## Client review history (closed)

Three source-review rounds ran in the client worktree, each fixed by its author and
merged here:

1. `79caeab` → `681d74c`: centralized pre-logout cleanup in `SessionController`,
   owner-bound captured credentials, rotation listener rechecks preference and
   permission and cleans up instead of staying subscribed, and duplicate web
   background display removed (SDK display for notification payloads, custom display
   only for data-only).
2. `681d74c` → `f0f88a8`: same-owner cleanup refreshes the Auth credential and falls
   back to the old owner's captured credential before unregistering, and the worker
   registers its safe same-origin click handler before importing the Firebase SDK,
   with a realistic SDK listener-order test.
3. Read-only recheck of `f0f88a8` cleared both remaining findings; no confirmed
   client blockers remain.

The integration readiness gate (`notificationContextKey`, MFA/password-pending and
no-active-context suppression) is preserved in the merged tree.


