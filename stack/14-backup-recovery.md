# Backup and recovery: offline prototype, activation blocked

**There is no backup workflow, scheduled backup, remote upload, retention or live backup configured by this change.** `scripts/backup/archive.py` is an offline packaging prototype, not a complete production backup system. It never connects to a database or Storage and never deletes remote objects. No provider or credentials were accessed during its validation.

## Activation blockers

Before implementing/activating a weekly workflow, the operator and security reviewer must approve all of the following:

1. An actual shared-Storage budget and reservation strategy. The 1 GB Free allocation is shared with public/private assets and backups; the 500 MB database limit does not imply three encrypted dumps plus a fourth in progress fit. Retention cannot free previous copies *before* a verified replacement. Provider quota/account usage and incomplete uploads must be accounted for safely. Fail closed and alert when no headroom; no paid/card fallback is approved.
2. DB dump scope, consistency and hosted restore strategy: Supabase-managed Auth, Storage metadata, extensions, roles, migration history and provider-managed schemas require separate review. A generic `pg_dump` is not evidence that hosted Supabase is recoverable. Test the precise approved dump and restore procedure against a disposable Supabase project before relying on it.
3. Scoped server-side Storage and database credentials, their ownership, rotation and incident response; demonstrate that the selected API supports bounded listing, upload, read-back and deletion without exposing credentials. Supabase S3 credentials may be broad: review effective permissions rather than assuming bucket scoping. Never put them in app code or PR jobs. Select an operator-approved key custodian and offline recovery process.
4. A transactional, concurrency-safe remote publication protocol with run-specific object namespaces, verified read-back, authenticated manifest and a commit marker; a failed or partial run may clean up only its own known objects. Inventory and prune only recognized, independently verified completed backups after successful publication; leave unknown objects untouched. Handle interrupted pruning and concurrent/manual runners; retain at least the newest three, and never trust timestamps supplied by an untrusted manifest. The offline prototype implements **none** of these remote guarantees.
5. A protected GitHub environment with required reviewers, no self-approval where supported, and branch restriction to protected main; confirm the repository plan actually enforces those settings before storing secrets. A YAML environment name alone is not protection. Agree how weekly schedules interact with required approvals, alerting and operator absence; do not disable approval to make cron work. Scheduling and any first backup need separate authorization.

Until these decisions and an independently reviewed/tested implementation exist, **do not add a cron, provision backup credentials, upload a production dump, or prune the bucket**. The intended destination remains the existing private `educador-backups` bucket, not a new service. Its object cap is 50 MB; provider quota values must be rechecked. Uploaded covers, avatars, PDFs, audio, GIFs and image sequences are separate object bytes: a DB dump only contains metadata/references. YouTube videos remain on YouTube. No object backup, object recovery, or offsite disaster protection exists here. The backup bucket is in the same provider/project, so it is not an independent disaster-recovery location.

## Offline archive format and verification

For experiments only, generate an encryption-capable GPG key on a trusted machine; keep the private key offline, encrypted and backed up in a separately secured location with a tested recovery custodian. Export only the verified public key to the packaging environment. Verify its full fingerprint out of band. Losing the private key makes the archive unrecoverable. Never upload private keys, dumps, passwords or GPG home directories as CI artifacts, logs or repository files. The prototype does not generate database dumps and does not protect plaintext on disk: use an encrypted private scratch directory, `umask 077`, sufficient space and independently managed cleanup. Secure deletion on SSDs or hosted runners cannot be assumed.

```bash
umask 077
python3 scripts/backup/archive.py pack /secure/scratch/dump.sql /secure/scratch/archive --recipient ENCRYPTION_FINGERPRINT --signer SIGNING_FINGERPRINT
python3 scripts/backup/archive.py unpack /secure/scratch/archive /secure/scratch/verified.sql --signer SIGNING_FINGERPRINT
```

This prototype requires Linux with `/proc` and `renameat2`. Encryption ignores GPG configuration and disables configured extra recipients; the specified encryption fingerprint is the only intended recipient. Version 2 signs the exact manifest with a separate signing key and verifies it against the independently trusted full primary signing fingerprint before reading ciphertext or decrypting. Version 1 unsigned archives are rejected. A signature authenticates the signer, not freshness: replay and compromised signing keys remain risks. Limits are enforced on actual source, compressed, ciphertext and decompressed bytes (600 MB each); parts are at most 40 MB. Linux directory descriptors, no-follow opens and atomic no-replace publication prevent pathname substitution and overwrite. Parent directories must exist and be trusted against untrusted writers. Scratch directories are private, but crashes or SIGKILL can leave plaintext behind: use encrypted scratch and arrange operator cleanup; secure deletion is not guaranteed.

Generate a distinct signing key. Protect its private key and passphrase in a reviewed, restricted CI environment with approved access and rotation, never PR jobs; use an agent or protected file descriptor for passphrases, never command-line arguments or logs. The packer only needs the encryption public key, while the restore environment holds the encryption private key and independently verified signing public key. No CI signing-key integration is implemented or approved here; do not activate unattended backups until it is reviewed and tested.

## Disposable restore verification

```bash
BACKUP_DOCKER_TEST=1 python3 -m unittest discover -s scripts/backup -v
```

This creates a fresh Docker `postgres:16` container without network access or published ports, creates a fixture database, dumps it, packages and unpacks it, restores into a second fresh database in that container, verifies a row and removes the container. It cannot restore to a supplied URL or live database. Docker image availability and daemon access are required. This tests only a generic PostgreSQL fixture, not hosted Supabase, Auth, permissions, extensions or Storage. No live restore command is provided: recovering a hosted instance requires a separately reviewed plan and explicit operator approval. Do not point generic SQL restore at production.
