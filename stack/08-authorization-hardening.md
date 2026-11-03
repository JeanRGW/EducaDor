# Authorization write boundaries

## Verified gaps and narrow changes

The pre-hardening schema gave `authenticated` column UPDATE privileges on own
profiles, including `needs_password` and `avatar_key`. The own-row policy prevented
identity crossover but did not enforce `update_own_profile` input validation.
Clients now read profiles and call that existing RPC for supported name, phone,
birth-date and address changes. Avatar editing is not implemented.

`lesson_progress` INSERT/UPDATE grants previously permitted callers to supply
`updated_at` directly, distorting latest-activity reports. Those grants are now
revoked; `save_employee_progress` owns inserts and timestamps, preserves completed
status and checks the active employee/company and lesson access. Existing gestor
DELETE access is unchanged. Completion remains client-reported: this does not
prove attendance, watch time, quiz correctness or historical engagement.

Storage public-object policies previously checked only bucket and active gestor.
Mutations now also require `covers/<alphanumeric-or-underscore-or-hyphen>.webp`,
matching the current publishing RPC's approved key shape. UPDATE checks both old
and new names, so renames cannot escape the prefix. Public SELECT is unchanged,
including legacy objects. This does not inspect object bytes, enforce declared
MIME on arbitrary SQL requests, or restrict server S3 keys (which bypass RLS).
The upload-signing function and bucket limits remain separate boundaries.

Certificates and redemptions already had no client write policies. Removing their
unreachable write grants is least-privilege defense in depth, not a newly fixed
RLS exploit; issuance/redemption use existing guarded server/RPC flows.

## Password onboarding is not authorization

`needs_password` is a UI onboarding flag. Context selection and content access do
not use it as an authorization gate. Invite/recovery bearer sessions are valid
Auth sessions; this change does not forbid their authorized DB access or demand
password reauthentication. Never describe this flag as proof of password change.

`AuthRepository.updatePassword` first awaits Supabase Auth's `updateUser`, then
calls `complete_password_setup`. That no-argument RPC derives identity exclusively
from `auth.uid()` and checks that `auth.users.encrypted_password` is nonempty
before clearing the caller's flag. It reads/locks one Auth row, returns no Auth
fields and never writes Auth tables. It rejects NULL/empty password state and is
idempotent after a password exists. A failure after Auth succeeds can be retried;
there is no distributed transaction across Auth and PostgREST.

Evidence: Supabase Auth's `internal/models/user.go` defines `HasPassword()` as a
non-NULL, nonempty `EncryptedPassword`; `NewUser` leaves an empty password hash
when no password is supplied, and `SetPassword`/`UpdatePassword` persist the Auth
managed hash. Reviewed source:
https://github.com/supabase/auth/blob/master/internal/models/user.go
Local pinned CLI database inspection also confirms `auth.users.encrypted_password`
is nullable text/varchar. No schema or grants on managed Auth objects are added.

Presence does **not** prove that a password changed during this session, that the
caller knows it, or that a password was recently reauthenticated. AMR describes
session authentication methods, not reliable evidence of a subsequent password
update. Auth's general `updated_at` is also not password-specific. Stronger
password-change/reauthentication policy needs an explicitly designed Auth boundary
and operator approval, not an unguarded flag toggle or application writes to Auth.

## Local verification and rollout

`supabase/tests/authorization_hardening.sql` covers direct malicious profile and
progress writes, password absence/presence and identity scope, own-profile RPC
success/validation, employee RPC timestamp/completion, cross-company and manager
rejection, invalid public keys/rename and anonymous public reads. Existing SQL
fixtures retain historical data through privileged setup, not restored client
grants. Flutter repository tests assert Auth-before-RPC ordering and that failed
Auth updates cannot clear onboarding state.

Generate from declarative files with pinned CLI 2.122.0; apply the generated
migration before shipping the new Flutter repository after operator approval.
Older Flutter builds cannot directly clear the profile flag once grants are
revoked; coordinate rollout accordingly. This work performs local validation only;
no hosted migration, Auth configuration, Edge Function or hosting deployment.
