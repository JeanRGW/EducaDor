# Implementation gap review and parallel delivery plan

Audit baseline: `main` at `6f203da`. Static analysis, 240 Flutter tests, SQL
regressions and ten invitation-handler tests passed before implementation.
This compares `stack/` contracts with production call sites, not just roadmap
headings. Local checks do not establish hosted configuration or device readiness.

## Delivery contract

- Each stream has a branch and persistent worktree under
  `/home/jean/github/EducaDor-worktrees/`; temporary directories do not survive
  harness restarts. Agent sessions must point to their persistent directories.
- Agents implement, test, build, commit, push and open PRs to `main`. They must not
  merge, deploy, change hosted data/secrets or provision services.
- Flutter analysis, focused/full tests and release builds use branch-local
  artifacts. Serialize heavy validation with a shared advisory lock and use
  `flutter test --concurrency=2` to bound memory use.
- Schema streams use independent local project IDs/ports. Never reset the shared
  `supabase_db_EducaDor` instance or linked project. `scripts/db.sh test` currently
  hardcodes that container: run suites against the stream's explicitly named
  local container instead.
- Edit declarative SQL, generate migrations with the pinned CLI and verify drift
  and all SQL suites. Never hand-edit generated history. Restore temporary local
  configuration before committing.
- Review grants, old-client compatibility and the combined migration chain.
  Independently passing PRs are not an integration test.

## Assigned independent workstreams

These are assignments, **not completion claims**. PRs and test logs establish
delivery; no implementation PR is implicitly merged or deployed.

| Branch | Intended result | Ownership / boundary |
| --- | --- | --- |
| `feat/content-lesson-points` | Author per-lesson points; preserve omitted values for old callers | Lesson editor and `save_content_lesson`; no new reward rules |
| `feat/company-code-prefix` | Edit certificate prefixes in company details | Company model/repository and `update_company`; existing codes unchanged |
| `feat/directory-pagination` | Server-side search/page managers and responsible professionals; page/retry pending invites | People/invitation repositories and directory RPCs; no revocation permission changes |
| `feat/auth-recovery` | Recover session refresh after accepted invitation without replaying its token | Onboarding UI; distinguish password partial-success boundaries |
| `feat/ui-completeness` | Honest notification availability, safe direct-route back action, empty ranking and accessible switches | Existing UI only, not notification delivery or redesign |
| `ci/delivery-checks` | No-secret Flutter/Function PR checks; gated Pages deploy and keepalive tooling | Workflows/scripts; deployment manual/unrun, DB activity semantics explicit |
| `fix/storage-hardening` | Reproducible SDK imports and tested auth/MIME/key/size/CORS/signing | Storage Functions and mocked tests; no hosted credentials or real uploads |
| `fix/authorization-hardening` | Guard profile/progress mutation and public object write prefixes | Grants/RPCs/policies and AuthRepository; verify password evidence, not an unrestricted flag RPC |
| `fix/pwa-reliability` | Avoid stale root bundles; harden headers and bound offline-shell behavior | Static hosting/app shell; never cache Auth/API/private data or bearer links |

Shared-file ownership: prefix owns `CompanyRepository`; directories own
`PeopleRepository`/`InvitationRepository`; authorization owns `AuthRepository`.
Points avoids repository changes. Do not reformat the entire shared file.

## Remaining implementation and prerequisites

| Capability | Gap / prerequisite | Next action |
| --- | --- | --- |
| Large uploads | Picker buffers whole file and uses one PUT despite a documented chunked path above 5 MB | Follow storage/points with S3 multipart, bounded-memory selection, retry/abort and synthetic 25 MB test |
| Push backend | No `push-on-assign`, recipient resolution, invalid-token cleanup or bounded sends | Resolve assignment/certificate event semantics; mocked backend can precede Firebase setup |
| Push clients | No Firebase initialization, token lifecycle, web worker or VAPID config | Operator supplies project/config; code must remain disabled without valid configuration |
| Backups | No dump/upload/retention/restore tooling | Approve encryption/key custody and capacity policy; no paid/external storage assumed |
| Backup capacity | 50 MB object cap and 1 GB shared Storage conflict with three near-limit DB dumps | Encrypted compressed chunks plus manifest still need an explicit total budget and fail-closed retention |
| Restore coverage | DB dumps do not include lesson objects; no recovery drill | Isolated restore/checksum tests; document DB-only coverage and object-loss risk |
| Keepalive activation | HTTP health/root success does not prove DB activity resets pause timing | Authenticated DB operation, server-only credential and explicit enablement |
| Deployment activation | Cloudflare Actions secret/environment protection are operator-owned | Manual workflow only until configured/reviewed; do not run from PRs |
| Production target | Only staging project/config is defined | Operator chooses project/domain/Auth URLs within free-project limits |
| Invite throttling | Admin invite generation lacks application quotas | Define limits without event-log tables or an unbounded counter service |
| Usage restrictions | Warning/restriction promise lacks implementation | Define measurement sources/behavior; no invented billing APIs or paid monitoring |
| Session cleanup | Retained selected contexts lack expired-session pruning | Prove safe cleanup against Auth lifetime; preserve active state |
| Bootstrap tests | First-gestor script has no tracked tests | Mock requests and never print bearer setup links |

## Explicit deferrals and undefined product rules

Operator decision during this review: **keep deferred gates**. Finish the
release-gap PR batch; do not bring deferred FCM/exports/avatars/MFA into scope
without a subsequent decision. External setup and deployments remain separately
approved even for implemented tooling.

These are not silently counted as implemented or promoted to this release:

- MFA/TOTP and `aal2`; verify the current Supabase plan rather than stale config
  comments. Never introduce paid MFA/SMS under the locked stack.
- Exports, credential settings, avatars, notification preferences, dark mode,
  languages, chat/support, departments and automatic reminders.
- Leave status, regulatory thresholds, certificate validity/renewal, levels,
  true streaks and study hours have no approved rules/data.
- Per-company reward catalogs, reward administration, employee offboarding and
  public certificate verification need explicit lifecycle/security requirements.
- Server-side grading/anti-cheat remains deferred. An unused score column does
  not authorize inventing assessment rules; completion remains client-reported.
- LGPD export/erasure and privileged audit trails need privacy/retention decisions;
  event-log tables remain forbidden by the current contract.
- Company-manager revocation remains platform-only with last-manager guards.
- Corporate YouTube blocking requires whitelisting. R2/Stream/Bunny are not
  approved fallback provisioning under the zero-cost/no-card stack.

FCM is contradictory across docs: the architecture plans it while the employee
release explicitly defers it. Separate planned architecture from availability
until scope and configuration are confirmed.

## Already implemented / documentation drift

Course-first authoring, module/lesson ordering and deletion, GIFs, still images,
sequences, MP3, PDF, reading and client-graded quizzes already exist. All formats
support accompanying text. Private downloads/playback, progress, certificates,
redemption and shared profile editing also exist. Do not rebuild these from
obsolete roadmap paragraphs.

The old atomic publisher and old lesson-edit methods have obsolete/orphaned UI
callers. Mock-only repository cleanup must follow integration with call-site
verification/full tests, not restore the old publisher or delete unfamiliar work.

## Review and integration order

1. Review CI/documentation contracts and storage test infrastructure.
2. Review authorization grants and Auth evidence separately.
3. Review points, prefix and directory migrations in an explicit order. Rebase
   and regenerate if needed; never hand-edit generated/deployed history.
4. Review onboarding/UI, then storage/PWA behavior in a browser.
5. Rebuild a fresh integration DB with accepted migrations; check drift and every
   SQL/Function test, Flutter analysis/full tests and release build.
6. Test role switches, sensitive links, offline behavior and uploads together.
   Confirm deployment jobs cannot run on PRs.
7. Merge only on operator instruction. Hosted migration/function/web deployment
   and scheduled-job activation are separate approved actions.
