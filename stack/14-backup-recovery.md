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
python3 scripts/backup/archive.py pack /secure/scratch/dump.sql /secure/scratch/archive --recipient FULL_UPPERCASE_FINGERPRINT
python3 scripts/backup/archive.py unpack /secure/scratch/archive /secure/scratch/verified.sql
```

It gzip-compresses, encrypts with GPG, then splits the ciphertext into 40,000,000-byte maximum parts (below 50 MB) and writes a manifest of sizes and SHA-256 hashes. Total encrypted size is capped at 600,000,000 bytes as a local resource limit, **not** a reservation or a claim that even one archive fits the provider quota. GPG checks ciphertext integrity on decrypt; hashes detect missing, truncated and altered chunks. The manifest is not signed: hashes alone do not authenticate the source, and public-key encryption alone does not establish who produced it. A replaced complete archive can still decrypt successfully. Never use this format for unattended remote retention without authenticated metadata and source verification. The output is only exposed after all parts, decryption and gzip verification succeed; destination overwrite is rejected. Unpacking does not limit decompressed output size; only process trusted, resource-bounded archives in a restricted scratch environment.

## Disposable restore verification

```bash
BACKUP_DOCKER_TEST=1 python3 -m unittest discover -s scripts/backup -v
```

This creates a fresh Docker `postgres:16` container without network access or published ports, creates a fixture database, dumps it, packages and unpacks it, restores into a second fresh database in that container, verifies a row and removes the container. It cannot restore to a supplied URL or live database. Docker image availability and daemon access are required. This tests only a generic PostgreSQL fixture, not hosted Supabase, Auth, permissions, extensions or Storage. No live restore command is provided: recovering a hosted instance requires a separately reviewed plan and explicit operator approval. Do not point generic SQL restore at production.
