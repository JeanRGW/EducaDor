# Security and push: combined integration

## Status

Combined integration branch `feat/security-push-integration`, based on `main`
`62d6460`, merges the completed source branches in this order:

| Source | Head merged | Pull request |
| --- | --- | --- |
| `docs/security-push-round` | `aad3e2d` | #17 |
| `feat/optional-totp` | `d592a13` | #19 |
| `feat/fcm-backend` | `768f46e` | #18 |
| `feat/fcm-client` | `681d74c` | #20 |

The integration branch is a review vehicle, not a release. It is not merged into
`main`, not deployed and it changes nothing hosted. Feature history repeats inside
the merge until the source PRs land; that is expected and resolves once the
dependencies merge in order. Source PRs remain independently reviewable.

**Status: not ready.** Client source `79caeab` was merged and validated here, then
`681d74c` was merged after the first independent client review. That head resolved
the revoked-permission rotation listener, the blocked opt-out while permission is
denied, and the duplicate web background display. A recheck of `681d74c` still
found two blockers (see "Remaining client blockers"), so this branch stays draft.
The full SQL/Node/Deno combined run below was repeated on `681d74c`; earlier
Flutter/build/browser evidence is from `79caeab` and has not been rerun on the
newer client.

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

SQL, drift, Node and Deno below were rerun on the merged `681d74c` client head.

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
- `node --test supabase/tests/invite_member.test.mjs scripts/pwa/*.test.mjs` pass.
- `deno test supabase/functions/push-on-assign/push_test.ts` (installed Deno 2.9.6)
  passes; `deno check` passes for `push-on-assign`, `issue-certificate`,
  `invite-member` and `accept-invite` entry points.
- Verified-caller review: `_shared/invites.ts#caller()` calls the caller-context
  `require_mfa_if_enrolled` RPC before returning the service-role client. The real
  entry points (`push-on-assign`, `issue-certificate`, `invite-member`,
  `accept-invite`, `_shared/storage_runtime.ts`) all call `caller()`; the mocked
  sender test does not stand in for that inspection.
- Flutter under the shared lock with `--concurrency=2` was run on the earlier
  `79caeab` merge: `flutter analyze`, full `flutter test` (288 tests), release web
  build with `--dart-define-from-file`, shell worker generation, and the 10 PWA
  worker tests passed. Widget tests also assert the configuration-off tile text and
  that the push switch is disabled. Not rerun on `681d74c`.
- Browser smoke was run on the earlier `79caeab` release build, served locally, no
  hosted mutation and no Firebase configuration: welcome and login render,
  `/account/security` and `/mfa` redirect to `/login` for an unauthenticated
  visitor, the shell worker registers, the only cache is the public static shell and
  it contains no auth, API, token or private route entries, and no Firebase/FCM
  network requests occur. Not rerun on `681d74c`.

## Not covered / release gates

- No real Firebase project, web VAPID key, Android config or FCM service account;
  real delivery, permission UX and Android device behavior are operator gates.
- No hosted Supabase change; the new migration is not pushed.
- Lost-factor recovery, hosted TOTP configuration and MFA behavior of the hosted
  Auth service remain operator verification.
- The client branch's Android debug build was verified by its author and was not
  repeated here because the integration changes do not touch native code.

## Remaining client blockers (PR #20 source, pending)

Client `681d74c` fixed the first review's three findings: pre-logout cleanup is now
centralized in `SessionController.logout`, `PushLifecycle` captures owner-bound
credentials per registration and rechecks preference and permission on rotation
(cleaning up instead of staying subscribed), and the web worker only calls
`showNotification` for data-only messages so notification payloads are displayed
once. `681d74c` was merged and revalidated for SQL/Node/Deno here.

A read-only recheck of `681d74c` still found two blockers, being fixed in the source
worktree:

1. **Captured JWT is not refreshed for the same owner.** Ordinary long-session
   logout uses the JWT captured at registration, so a fresh Auth credential can be
   available while cleanup still fails. Fix direction: refresh the credential for the
   same owner before cleanup, falling back to the old owner's captured credential.
   Best effort only: a network failure or rejected credential can still leave a
   registration row, and a failed provider-token deletion cannot guarantee instant
   revocation.
2. **Worker click listener order.** The app click handler is registered after the
   Firebase SDK imports, so the SDK's `stopImmediatePropagation` prevents the safe
   root click handler from running. Fix direction: register the app handler before
   the SDK import and cover the realistic listener order with a worker test.

Revoked-permission handling and duplicate background display are cleared. The
integration readiness gate (`notificationContextKey`, MFA/password-pending and
no-active-context suppression) remains preserved in the merged tree. Full Flutter,
release build/worker and browser checks have not been rerun on `681d74c`; do that
after the corrected client head lands.

