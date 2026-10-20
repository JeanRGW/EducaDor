# Employee features

Implemented against all seven `EMP` images in `../Figma_Educador/screens`,
including both course-detail variants. Supabase remains the only backend;
YouTube remains the only video provider. No employee UI imports mocks.

## Screen map

| Route | Behavior |
|---|---|
| `/funcionario/home` | Identity/company header, real completion counts, first in-progress course and up to two eligible not-started recommendations. |
| `/funcionario/modulos` | Search before 50-row pagination, teal media filters, My Learning and Discover (eligible not-started courses only), covers and per-course progress. |
| `/funcionario/course/:id` | Cover, description, ordered module/lesson outline, resume/continue, explicit unsupported-format states and certificate retry. |
| `/funcionario/course/:id/lesson/:lessonId` | YouTube playback/resume, progress checkpoints, completion and safe exit/retry. |
| `/funcionario/progresso` | Course completion, current courses and paginated certificate history. The approximate weekly activity section was removed at design review. |
| `/funcionario/recompensas` | Derived balance, certificate PDF download, paginated active rewards, confirmed redemption and company Top 3. |
| `/funcionario/perfil` | Own name, membership department, company-scoped counts, role switching, logout and real own-profile editor. |
| `/funcionario/perfil/edit` | Reuses the existing authenticated profile RPC/editor; email/roles remain read-only. |

Headings, body text, covers, teal controls and SVGs reuse existing tokens.
Screens have mobile/desktop and enlarged-text coverage. Deep-link intent survives
session restoration and role selection; wrong-role destinations are discarded.
Imperative route pushes reflect in the browser URL so refreshing a course/player
does not silently return to the catalog. Direct back controls use a safe fallback.

Review refinements place the Modules title and learning/discovery selector on one
header row (stacked for enlarged text), use the supplied blue catalog accents,
and align Profile's badge/stats/settings with the prototype. Rewards uses a compact
horizontal gradient balance card, compact certificate/reward tiles and a mint
current-user ranking row. Levels are not fabricated; generic SVG illustrations
stand in for reward photos because the reward schema has no image field. Explicit
redemption confirmation and insufficient-balance states remain functional.

## Metric and authorization contract

* Every employee RPC validates the active **funcionario** context and expected
  company. A global gestor grant is not an employee-context substitute. Providers
  track user/company and scope every page key; old pages do not fetch data for a
  newly selected identity/company. RLS remains the content/security boundary.
* Home/Progress completion is completed **available courses** divided by available
  courses. A course is complete only when it contains at least one lesson and all
  its lessons are complete. Empty courses are never implicitly certified. A zero
  denominator is unavailable, not 0% success. Individual course bars use completed
  lessons / lesson count. Paused/ineligible courses are excluded from the active
  catalog; historical certificates and earned points are retained.
* Media filters refer to lesson kinds, not `courses.kind` (which describes a trail).
  Discover and recommendations never expose an unauthorized catalog. They are
  eligible not-started courses, not an inferred personalization service.
* Weekly activity is intentionally not displayed: latest-update data cannot
  reproduce the prototype's study-frequency behavior. No replacement approximation
  or invented history is shown. The existing summary response retains its activity
  field for compatibility; it is not used by the employee screens.
* Points and ranking use completed lessons' points minus current reward costs for
  company-scoped redemptions, retaining the existing derived-balance contract.
  Ranking includes identity IDs to highlight the actual signed-in employee.
  The old `ranking` RPC now fails closed for null/revoked contexts as well.

## Playback and progress

`youtube_player_flutter` 10 supplies web/Android/iOS playback. Video IDs and
positions come from guarded lesson metadata; the app never stores/uploads MP4s.
The player starts at saved `position_sec` and does not overwrite resume before
playback starts. Its position events drive checkpoints (15 seconds of position
change), pause, app-background and exit saves; there is no Supabase polling.
Duration is read from metadata or a bounded event-driven IFrame API fallback when
metadata arrives late. Unknown duration still permits resume saves, but cannot
qualify completion; the player offers reload rather than fabricating a duration.
Completion is client-reported position >=90% of the video;
the documented forgeable-client MVP risk remains. Unsupported lesson formats
cannot be marked complete through the video progress RPC.

Progress writes validate current role/company, content gates and nonnegative
position. They lock the selected session/membership/company and course during the
mutation. Completion is monotonic under upsert; restrictive policies also reject
ordinary direct downgrades. The policy helper is volatile so waiting concurrent
writes recheck committed completion. A nonnegative-position constraint is added
`NOT VALID` to protect new writes without silently rewriting legacy data; inspect
and repair any existing invalid rows separately before validating it.

Save failures stay retryable, and exiting without saving is explicit. A profile
change stops the old player and prevents queued saves from targeting a new company.

## Certificates and rewards

After saving a completed video, the app invokes `issue-certificate`; an incomplete
course is a normal non-issuance result. Course details also offer an explicit,
idempotent retry after all loaded lessons are complete. The Edge Function verifies
the bearer JWT, derives user/session from it (never the body), and invokes the
service-only `issue_employee_certificate` RPC. That RPC revalidates selected
session/membership/activity and all course gates, checks every lesson's company-
scoped completion, serializes competing issuance, and preserves the unique
user/company/course record. Codes use the company's prefix and six Crockford
base32 characters, with collision retry.

Historical certificate metadata is returned through a guarded RPC even when the
course is paused. The PDF is generated locally from that authorized record with
bundled fonts (`pdf` + `printing`); no new Storage object, font download, API or
public verification endpoint is introduced. Course/person/company names reflect
current retained metadata, not immutable issuance-time snapshots.

Redemption requires confirmation, a displayed balance and no concurrent UI submit.
`redeem_employee_reward` validates the expected company and locks context before
using the existing atomic balance-locking `redeem_reward`. An uncertain network
response disables another attempt until an explicit refresh; it is not silently
retried. This records a redemption, not inventory/delivery fulfillment.

## Intentional boundaries

Notifications/FCM, MFA, CSV/report exports, non-video authoring and playback,
professional chat, support workflow, dark mode and additional languages remain
deferred. The UI states availability rather than showing fake enabled settings.
Level thresholds, true streaks and study-hour tracking have no agreed rules/data;
their prototype values are not fabricated. The first learning flow is video-only;
quiz grading/pass rules and private PDF/audio download functions remain separate
work. Courses containing unfinished unsupported lessons cannot be certified.

## Review and deployment

Validation includes widget/repository tests, 320/418/1000px at 1.0/1.8 text scale,
PDF generation, playback-save serialization, selected-context changes, deep links,
SQL authorization/gates/monotonic progress and local concurrent issuance/redemption.
Browser preview uses isolated test repositories, not staging Auth or data.

Nothing is applied or deployed implicitly. Deployment order, after approval:

1. Apply `20261010000000_employee_features.sql` to staging; run the SQL tests on an
   isolated database first. Never rewrite already-applied migrations.
2. Deploy `issue-certificate` with `--no-verify-jwt` (the function performs verified
   `getUser` authentication itself, like the existing invitation functions).
   Existing `SUPABASE_*` secrets and app-origin allowlist are required.
3. Build/deploy Flutter, then smoke-test employee and manager contexts on staging.

Android release Internet permission is included. Physical-device playback/PDF
handoff and staging auth/end-to-end delivery remain operator review checks before
shipping; local tests do not establish deployed state.
