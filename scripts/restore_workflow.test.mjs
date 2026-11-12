import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = readFileSync(new URL('../.github/workflows/restore-drill.yml', import.meta.url), 'utf8');
const script = readFileSync(new URL('../scripts/backup/hosted_restore.py', import.meta.url), 'utf8');

test('restore drill is manual, main-only and explicitly confirmed', () => {
  assert.doesNotMatch(workflow, /^  schedule:/m);
  assert.match(workflow, /^  workflow_dispatch:\n    inputs:\n      confirm:\n        description: [^\n]+\n        type: boolean\n        required: true\n        default: false$/m);
  assert.match(workflow, /^      dry_run:\n        description: [^\n]+\n        type: boolean\n        required: true\n        default: true$/m);
  assert.match(workflow, /if: github\.ref == 'refs\/heads\/main' && inputs\.confirm == true/);
});

test('restore drill uses the protected environment with bounded concurrency', () => {
  assert.match(workflow, /^permissions:\n  contents: read$/m);
  assert.match(workflow, /^concurrency:\n  group: hosted-restore-drill\n  cancel-in-progress: false$/m);
  assert.match(workflow, /^    environment: backup-production$/m);
  assert.match(workflow, /^    timeout-minutes: 30$/m);
});

test('restore drill uses isolated pinned tooling and PostgreSQL 17', () => {
  assert.match(workflow, /setup-python@[0-9a-f]+ # v5\.6\.0/);
  assert.match(workflow, /python-version: '3\.12'/);
  assert.match(workflow, /'awscli==1\.36\.40'/);
  assert.match(workflow, /apt\.postgresql\.org\/pub\/repos\/apt/);
  assert.match(workflow, /apt-get install -y postgresql-client-17/);
  assert.match(workflow, /PSQL="\$PGBIN\/psql"/);
  assert.match(workflow, /"\$PSQL" --version \| grep -E/);
  assert.match(workflow, /echo "\$PGBIN" >> "\$GITHUB_PATH"/);
});

test('restore drill imports temporary decryption material into a dedicated GNUPGHOME', () => {
  for (const secret of ['BACKUP_HMAC_KEY_HEX', 'BACKUP_GPG_PRIVATE_KEY', 'BACKUP_GPG_PASSPHRASE',
                        'BACKUP_DATABASE_URL', 'BACKUP_S3_ACCESS_KEY_ID', 'BACKUP_S3_SECRET_ACCESS_KEY']) {
    assert.ok(workflow.includes(`secrets.${secret}`), `missing environment secret ${secret}`);
  }
  assert.match(workflow, /export GNUPGHOME="\$work\/gnupg"/);
  assert.match(workflow, /printf '%s' "\$BACKUP_GPG_PRIVATE_KEY" > "\$work\/private-key\.asc"/);
  assert.match(workflow, /chmod 600 "\$work\/private-key\.asc"/);
  assert.match(workflow, /gpg --batch --quiet --import "\$work\/private-key\.asc"/);
  assert.match(workflow, /rm -f "\$work\/private-key\.asc"/);
  assert.match(workflow, /printf '%s' "\$BACKUP_GPG_PASSPHRASE" > "\$work\/passphrase"/);
  assert.match(workflow, /chmod 600 "\$work\/passphrase"/);
  assert.match(workflow, /unset BACKUP_GPG_PRIVATE_KEY/);
  assert.match(workflow, /unset BACKUP_GPG_PASSPHRASE/);
  assert.match(workflow, /BACKUP_GPG_PASSPHRASE_FILE="\$work\/passphrase"/);
  assert.match(workflow, /gpg --batch --list-keys "\$BACKUP_SIGNER_FINGERPRINT"/);
});

test('restore drill runs dry-run first by default and cleans up always', () => {
  assert.match(workflow, /DRY_RUN: \$\{\{ inputs\.dry_run \}\}/);
  assert.match(workflow, /args\+=\(--dry-run\)/);
  assert.match(workflow, /python3 scripts\/backup\/hosted_restore\.py "\$\{args\[@\]\}"/);
  const cleanup = workflow.slice(workflow.indexOf('- name: Remove scratch'));
  assert.match(cleanup, /if: always\(\)/);
  assert.match(cleanup, /gpgconf --kill gpg-agent/);
  assert.match(cleanup, /rm -rf "\$RUNNER_TEMP\/educador-restore"/);
  assert.doesNotMatch(workflow, /set -x/);
  assert.doesNotMatch(workflow, /echo[^\n]*PGDATABASE|printf[^\n]*PGDATABASE/);
});

test('restore script is atomic and never echoes secrets', () => {
  assert.match(script, /\['BEGIN;', \*truncates, body, \*verify, 'COMMIT;'\]/);
  assert.match(script, /TRUNCATE TABLE \{_quote_identifier\(schema\)\}/);
  assert.match(script, /\('auth', 'schema_migrations'\)/);
  assert.match(script, /'--single-transaction', '-f'/);
  assert.match(script, /ON_ERROR_STOP=1/);
  assert.match(script, /Never echo the exception text/);
  assert.match(script, /changes were rolled back/);
  assert.match(script, /BACKUP_EXPECTED_PROJECT_REF/);
});
