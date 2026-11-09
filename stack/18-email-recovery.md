# Email password recovery

## Flow

`/recover` requests a Supabase Auth recovery email. The confirmation is the same
for existing and unknown accounts; there is no account lookup in the client. A
60-second local resend cooldown complements Auth's server-side rate limits.

The SMTP template at `supabase/templates/recovery.html` links to the fixed app
callback `/recover/complete#token_hash=...`. Keep the token in the fragment, not a
query parameter, so it is not transmitted in the Pages HTTP request or referrer.
The callback never displays the token and requires an explicit **Continuar** action
before calling `verifyOTP(type: recovery)`, reducing accidental consumption by
email-link scanners. Successful verification navigates to `/reset-password`,
removing the bearer fragment. Invalid, expired and consumed links offer a new
request. Do not log links, hashes, OTP codes, passwords or full Auth errors.

Recovery requests use an isolated public Auth client without PKCE state: the
hash-based email link works in a different browser/device without a verifier from
the requesting browser. The primary application's Auth flow is unchanged.

## Session and MFA boundaries

Supabase's POST recovery verification currently issues an `otp` AMR entry, not a
distinct `recovery` AMR entry. Therefore AMR alone must not infer recovery intent.
After the Auth-verified recovery response/event, the client stores only that
session's UUID in tab-scoped sessionStorage (memory fallback on other platforms).
It never stores the bearer link in this marker. The marker is UI intent, not an
authorization grant. `getUser()` still verifies the session server-side, the
session ID must match, and the Auth method must be OTP/recovery. A normal password
session or another session's marker cannot enter the recovery form.

The marker survives same-tab refresh when sessionStorage is available and is
cleared on sign-out, password sign-in or a mismatched session. A newly opened tab
without a valid recovery link may need a new link. No persisted DB flags or event
tables are added. Stale session refreshes cannot overwrite a newer recovery or
signed-out state.

Verified MFA factors are retained. Enrolled AAL1 sessions go through the existing
TOTP challenge before password mutation; after AAL2, routing resumes the recovery
form rather than role selection. Existing DB/Edge MFA enforcement is unchanged.
Push registration is suppressed during recovery. Password recovery is not
lost-authenticator recovery and never removes factors.

Auth password update and onboarding-flag completion remain separate operations.
The form remembers successful stages, clears password fields, and retries only
unfinished completion/sign-out steps rather than replaying a successful password
change. It signs out the current recovery session and asks the user to sign in
again; it does not promise immediate revocation of other already-issued JWTs.

## SMTP configuration (operator-owned, never app credentials)

The approved provider is the existing Resend account/domain `rgw.app`, using
`EducaDor <educador@rgw.app>`. Supabase Auth SMTP uses `smtp.resend.com:465`, user
`resend`, and a dedicated domain-restricted sending key as its password. The key
belongs only in hosted Auth SMTP configuration/protected operator storage, not
Dart, public build JSON, Functions secrets or committed workflows.

Set the recovery subject to **Redefina sua senha — EducaDor**, install the HTML
template through the Auth configuration API/dashboard, and allow exactly
`https://app.educador.rgw.app/recover/complete` in addition to existing redirects.
Do not push the repository's localhost `supabase/config.toml` to the hosted project.
Preserve disabled public signup, email confirmation, existing hooks and TOTP
settings. Keep link/open tracking disabled for authentication mail; do not change
tracking on a shared sending domain without its owner's review.

Initial Auth sending cap: 10 emails/hour, retaining a one-minute recipient
cooldown. Resend Free allows 100/day and 3,000/month shared with other apps and test
emails. No billing changes, pay-as-you-go, custom mail API, queue or new SMTP proxy
are needed. Provider acceptance does not prove receipt in a person's inbox.

## Verification and rollout

- Run repository/widget/routing/session-race tests, full Flutter analysis/tests,
  the configured release build, shell-worker generation and Node template/PWA tests.
- Verify callback fragments survive direct entry and refresh, are removed after
  redemption and never appear in CacheStorage. Auth/recovery routes use no-store;
  the worker serves only its sanitized public index for navigation.
- Check the email flow with Resend's `delivered+label@resend.dev` simulation
  address, not invented inboxes that can damage domain reputation. It consumes
  quota and does not establish human inbox delivery. Use disposable Auth accounts
  and privately generated recovery hashes to test password replacement, replay
  rejection, refresh, MFA and cleanup without changing an operator account.
- Configure SMTP/template and the callback allowlist, then publish the matching
  reviewed PWA. Confirm the hosted config changes only the intended fields.
- A trusted operator can still hand off a freshly generated recovery hash via
  the same app fragment callback when email is unavailable, after independent
  identity verification. Never expose an admin recovery-link generator publicly.
