# Security and push: current implementation round

## Status and boundaries

Baseline is `main` at `62d6460`: the previous ten-PR batch is merged, **not
deployed**. This document defines planned work, not proof of implementation,
integration, hosted configuration or delivery. Each PR and its test output provide
implementation evidence; deployment requires separate operator approval and
verification. No agent merges, deploys, provisions hosted services, alters hosted
data/secrets, or resets a shared database. No automatic merges.

This round covers optional account TOTP and FCM notification delivery, plus only
critical feature authorization, token privacy, worker integration, config-off
safety and relevant tests. Backups, multipart uploads, invitation quotas and other
roadmap gaps remain next-round work, not prerequisites invented for these PRs.

## Parallel streams and contracts

| Branch / owner | Scope | Coordination |
| --- | --- | --- |
| `feat/optional-totp` | MFA auth, router, security screen and server guards; `stack/13-account-mfa.md` | Expose `/account/security` route for profile navigation; protect enrolled users in every relevant server path; no `SecuritySettingsTile` needed |
| `feat/fcm-backend` | `push-on-assign`, SQL preferences/tokens and authorization; `stack/14-fcm-backend.md` | Publish typed event, preference and token contracts for client; no arbitrary recipient/message input |
| `feat/fcm-client` | Firebase dependencies, initialization, worker/transport lifecycle, course/certificate hooks and profile wiring; `stack/15-fcm-client.md` | Own `lib/shared/widgets/profile.dart` `ProfileAccountSettings`: insert `NotificationSettingsTile` and a simple security menu row navigating to `/account/security`; coordinate backend contract and worker scope; safe with configuration absent |
| Coordinator | Combined integration and review | Resolve shared-file conflicts and verify end-to-end contracts without claiming independently passing branches are integrated |
| `docs/security-push-round` | Architecture and this plan only | Document intent and evidence separately |

Each agent uses its own persistent worktree, runs focused checks, commits a
Conventional Commit, pushes its branch and opens a separate PR. Schema agents use
independent local Supabase project IDs and ports; never reset a shared instance or
linked database. Generate and review migrations from declarative schema, do not
hand-edit generated history. Serialize Flutter analysis, tests and builds with
`flock /home/jean/github/EducaDor-worktrees/.flutter-validation.lock`; keep test
concurrency bounded. PRs target `main` and remain open for review.

## Acceptance: optional TOTP

- Enrollment is voluntary for every account, including gestores; unenrolled
  accounts retain normal access. TOTP only, no SMS or custom recovery bypass.
- Enrollment, challenge, verification, unenrollment and session restoration have
  clear UI and error states. Enrolled accounts must challenge to `aal2` before
  protected use; server-side checks enforce this even for direct API/function
  calls or stale clients, not just router redirects. Context switches cannot bypass
  the check. Verify the actual Supabase factor/AAL semantics and plan availability.
- Tests cover unenrolled and enrolled accounts, expired/challenged sessions,
  multiple roles, direct server calls and failed verification. Never expose codes,
  secrets or recovery material in logs.
- Document an operator-managed lost-factor recovery procedure and its security
  requirements before release; do not assert a recovery bypass exists. Validate
  the procedure against hosted Auth behavior with operator approval.

## Acceptance: FCM

- Initial target is web/PWA and Android. Firebase configuration is disabled by
  default; missing or unsupported configuration leaves login, learning and
  certificate issuance functional without prompting or crashing. Permission is
  requested explicitly; a persisted account push preference is respected.
- Foreground/background handling, token creation/refresh and cleanup on sign-out,
  account switch and invalid FCM token responses prevent cross-account delivery.
  Treat registration tokens as private, limit access to their owner/service, and
  never log them. Test multiple accounts and devices, revoked permission and failed
  network operations; document platform limitations.
- Following a successful course availability mutation, the app can invoke
  `push-on-assign` with `course_available {course_id, company_id?}`; following
  successful server-side certificate issuance, with `certificate_issued
  {certificate_id}`. These represent existing state, not client-created
  assignment/certificate rows. Server authenticates and authorizes the event,
  resolves recipients from trusted data and checks platform release, company
  audience and company enablement. Certificate recipient and company derive from
  the issued record. Caller cannot specify users or arbitrary text.
- Direct FCM HTTP v1 sends are bounded, best effort and optional; a minimal
  current-state cooldown marker limits repeated sends. It is not an event log,
  queue, exactly-once guarantee or resend mechanism. Tests cover unauthorized and
  forged events, each access gate, preference, fanout bounds, cooldown, invalid
  token cleanup and partial failures. No inbox, topics, reminders or resend UI.
- The messaging worker must coexist with the generated static-only shell worker:
  no private, Auth, API or bearer-URL response caching. Test worker registration,
  update and notification handling alongside shell offline/navigation behavior.
  FCM's web VAPID **public** key is client configuration; HTTP v1 uses the FCM
  service-account secret server-side and needs no VAPID private key in Supabase.

## Integration, review and release gates

1. Independently review PRs and evidence, including authorization and privacy;
   coordinate interfaces and shared files before integration. Do not merge merely
   because an agent opened a PR.
2. In a combined isolated worktree and separate local Supabase project, reconcile
   declarative schemas and regenerate migrations as needed, without rewriting
   deployed history. Rebuild a fresh local database, check migration order and
   drift, and run all SQL and Edge Function regressions. Do not reset shared DBs.
3. Under the shared Flutter lock, run `flutter analyze`, full Flutter tests with
   bounded concurrency, release web build, shell worker generation and PWA tests.
   Exercise MFA, account/role switching, configuration-off behavior, push events
   and worker coexistence together; preserve logs and identify untested platforms.
4. Review PRs and integration evidence; merge only on explicit operator instruction.
   Before release, operator must provision/approve Firebase Spark project and FCM
   service account, web public config/VAPID and authorized origins, Android config,
   and verify supported browsers/devices, permission UX and real delivery. Verify
   Supabase TOTP support and lost-factor recovery. None is established by local tests.
5. Only after explicit operator approval, deploy reviewed migrations first, then
   matching Edge Functions/secrets, then the generated PWA build. Verify staging
   Auth, MFA, permission, token lifecycle, delivery and private caching on real
   supported devices; record deployed revisions and results. Android rollout is
   separately gated by its build/configuration and device checks. No hosted change
   or deployment is implied by a PR or this plan.
