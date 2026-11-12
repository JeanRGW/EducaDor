# Profile privacy rollout

The two generated migrations in this change are intentionally separate. The first,
`20261112053533_profile_rpc.sql`, is additive; the second,
`20261112053550_profile_restrict.sql`, removes table-wide authenticated SELECT and
permits only directory columns. **Do not run an ordinary unbounded `db push` while
both migrations are pending:** it applies both, without the compatibility pause.
Use an operator-reviewed, version-targeted migration mechanism that applies only the
first migration and verifies the recorded migration version. If the available tool
cannot target a version safely, stop and obtain an approved procedure; do not edit
migration history, mark unapplied migrations as applied, or use Studio SQL.

**Deployment blocker (2026-11-12):** no hosted version-targeted procedure has
been verified for the pinned CLI. Its `db push` and `migration up` help expose no
version limit. A truncated migration directory is a possible research direction,
not an approved hosted deployment mechanism: local testing does not establish
linked-project identity, credential handling, exact hosted history, or protection
against concurrent migration changes between inspection and application. Do not
use it on a hosted project until those safeguards have been independently reviewed
and an operator approves a complete procedure. An ordinary push, migration repair,
manual SQL, or a remote reset is not a workaround.

A local-only experiment used CLI 2.122.0 with a separate project ID, ports and
container, and copied unchanged migration files into a temporary workdir. Starting
from history through `20261110004654`, a `db push --local --skip-vault --dry-run`
listed only `20261112053533`; the subsequent local push recorded that version,
created `own_profile()`, and retained authenticated table-wide SELECT. After copying
`20261112053550`, a second dry run listed only that file; the local push recorded
it and removed table-wide SELECT. With both files present, declarative strict
coverage reported no schema changes. Removing the restriction file after it was
recorded made the local dry run fail with `DbPushMissingLocalError`; its suggested
migration repair must **not** be followed. This experiment did not contact or
validate a hosted project and does not establish safety for missing earlier versions,
concurrent deploys, or all unexpected histories.

| Client | Before additive RPC | Additive only | Restricted |
| --- | --- | --- | --- |
| Old PWA (direct sensitive SELECT) | Works; exposure exists | Works; exposure exists | Profile/session reads fail |
| New PWA (own_profile RPC) | Fails: RPC absent | Works; exposure exists | Works; exposure closed for authenticated clients |

The same authenticated database role serves every PWA version. There is no
indefinite zero-downtime compatibility for old tabs and privacy enforcement.
Until restriction is applied, same-company managers can still read other members'
sensitive profile fields directly. Service-role access remains privileged.

## Operator-controlled sequence

1. Schedule and announce a controlled maintenance/cutover, including the privacy
   risk during the transition. Obtain operator approval for the target and each
   deployment; take the normal backup and verify the target project and version.
2. Apply **only** the additive migration. Verify its migration record, RPC grants,
   own-profile and MFA behavior. Do not apply the restriction yet.
3. Publish the compatible PWA and verify fresh sessions, profile editing, gender,
   directories, and reporting. Coordinate managed client retirement: notify all
   users to save work, sign out and **close every app tab/window**, then reopen
   the app and verify the new version. Waiting alone or publishing a new service
   worker cannot prove that old tabs have stopped running. Record confirmation or
   a bounded retirement deadline and identify clients that cannot be confirmed.
4. An authorized operator must explicitly accept disruption to any unconfirmed or
   returning old clients before enforcement. If this decision is not made, stop:
   the privacy exposure continues. During the announced cutover, apply the second
   migration and verify its migration record, denied sensitive direct reads and
   `SELECT *`, new-client own-profile/MFA, and directories/reports. Old tabs must
   close all app windows and reload; they may fail until they do.
5. Monitor support and handle stranded clients. An emergency regrant of table
   SELECT is a **new forward migration**, requires explicit operator approval,
   and deliberately reopens the privacy exposure to same-company managers (and
   potentially other permitted directory readers). Announce and time-bound that
   decision, then generate another forward restriction migration when ready. Never
   silently regrant or rewrite an applied migration.

The original combined migration existed only on this undeployed PR and was
regenerated as these two stages. Never replace a migration after deployment.
