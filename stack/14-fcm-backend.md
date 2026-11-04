# FCM backend

## Contract

Authenticated clients call `register_fcm_token(p_token, p_platform)` with
`android`, `ios`, or `web`. Registration transfers that token to the current
identity without changing its preference; `unregister_fcm_token(p_token)` only
removes the caller's token. `set_push_enabled(p_enabled)` sets the preference;
read the caller's `notification_preferences` row (missing means enabled).
Direct client token writes are disabled: migrate existing clients before rollout.
Existing duplicate token owners are reconciled on re-registration.

POST `push-on-assign` with the verified user's JWT and exactly one of:

* `{ "event": "course_available", "course_id": "uuid" }` for a gestor's
  platform release or expansion to all companies;
* `{ "event": "course_available", "course_id": "uuid", "company_id": "uuid" }`
  for an added allowlist company (gestor), or a company resume (that company's
  active empresa or gestor);
* `{ "event": "certificate_issued", "certificate_id": "uuid" }` for the
  active employee's own newly issued certificate. Updated `issue-certificate` returns
  `{ "id": "uuid", "created": true|false }`; send only when `created` is true,
  using `id` as `certificate_id`. Older clients may continue reading `id`.

Call after the mutation succeeds, once per newly added allowlist company; do not
call on removals, pauses, repeated unchanged saves, or signups. The function
returns only `event`, `sent`, `failed`, `truncated`, and `suppressed`. The push
payload is generic pt-BR, and data contains only event and entity IDs; clients
must map these locally, never treat them as URLs.

The verified caller helper and caller-context check precede any service-role
operation. The service-only claim revalidates the JWT session's current role and
membership, requires active company, and resolves only employee tokens meeting
platform release, audience, company switch and push preference gates. Certificate
claims require the owner's matching employee context. Tokens and identities are
never returned to the caller. Claim state is stored on courses, assignments and
certificates, not a delivery log or queue. A claim is valid for ten minutes;
course/assignment claims have a five-minute cooldown. Unchanged enables do not
create a claim. Claims are consumed before sending; crashes, disabled preferences,
partial failures, cooldown or missing configuration can lose notifications.
Each call attempts at most 100 tokens with five concurrent sends and eight-second
per-request timeouts; `truncated` means additional recipients were not sent, with
no pagination/retry. Multiple eligible companies do not duplicate a token in a
single broadcast. Future company membership is not a push event.

FCM HTTP v1 uses an OAuth JWT signed locally with the server-only
`FCM_SERVICE_ACCOUNT_JSON` secret; no Firebase paid products are used. Only an
explicit FCM `UNREGISTERED` error deletes a token, conditional on owner and
registration timestamp so a concurrent registration is preserved. There are no
automatic retries. Gate checks are a snapshot at claim time; changes concurrent
with FCM delivery cannot revoke an already claimed message.

## Verification and rollout

Run SQL regressions on an isolated Supabase project, declarative drift check,
`node --test supabase/tests/invite_member.test.mjs`, `deno test
supabase/functions/push-on-assign/push_test.ts` (no permissions) and `deno check
supabase/functions/push-on-assign/index.ts`. The SQL tests cover token switching,
preferences, broadcast eligibility, cross-company denial, company resume and
certificate ownership. Mocked FCM tests verify OAuth signatures, partial failures,
invalid token classification and bounds. Hosted integration and device delivery
are not tested. MFA agent must review the combined branch's verified-caller and
context gates. Operator approval is required for migrations, function deployment,
Firebase project/service-account configuration, web VAPID setup and client rollout;
none was performed in this branch.
