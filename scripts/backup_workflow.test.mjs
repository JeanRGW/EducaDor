import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const backup = readFileSync(new URL('../.github/workflows/backup.yml', import.meta.url), 'utf8');
const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');

test('backup is activated on a daily schedule with confirmed manual dispatch', () => {
  assert.match(backup, /^  schedule:\n    - cron: '17 3 \* \* \*'$/m);
  assert.match(backup, /^  workflow_dispatch:\n    inputs:\n      confirm:\n        description: [^\n]+\n        type: boolean\n        required: true\n        default: false$/m);
  assert.match(backup, /github\.event_name == 'schedule' \|\| inputs\.confirm == true/);
});

test('backup guard requires main, BACKUP_ENABLED and manual confirmation', () => {
  assert.doesNotMatch(backup, /false &&/);
  assert.match(backup, /if: >-\n      github\.ref == 'refs\/heads\/main' && vars\.BACKUP_ENABLED == 'true' &&\n      \(github\.event_name == 'schedule' \|\| inputs\.confirm == true\)/);
});

test('backup secrets stay scoped to the backup-production environment', () => {
  assert.match(backup, /^    environment: backup-production$/m);
  for (const secret of ['BACKUP_DATABASE_URL', 'BACKUP_SIGNING_PRIVATE_KEY', 'BACKUP_HMAC_KEY_HEX',
                        'BACKUP_S3_ACCESS_KEY_ID', 'BACKUP_S3_SECRET_ACCESS_KEY']) {
    assert.ok(backup.includes(`secrets.${secret}`), `missing environment secret ${secret}`);
  }
});

test('backup imports encryption and signing public keys and checks both fingerprints', () => {
  assert.match(backup, /BACKUP_SIGNING_PUBLIC_KEY: \$\{\{ vars\.BACKUP_SIGNING_PUBLIC_KEY \}\}/);
  const publishStep = backup.slice(backup.indexOf('- name: Publish verified archive'),
                                   backup.indexOf('- name: Remove scratch'));
  assert.ok(publishStep.includes('printf \'%s\' "$BACKUP_PUBLIC_KEY"'));
  assert.ok(publishStep.includes('printf \'%s\' "$BACKUP_SIGNING_PUBLIC_KEY"'));
  assert.ok(publishStep.includes('for fpr in "$BACKUP_RECIPIENT_FINGERPRINT" "$BACKUP_SIGNER_FINGERPRINT"; do'));
  assert.ok(publishStep.includes('gpg --batch --list-keys "$fpr"'));
  const packStep = backup.slice(backup.indexOf('- name: Encrypt and sign'),
                                backup.indexOf('- name: Publish verified archive'));
  assert.ok(packStep.includes('printf \'%s\' "$BACKUP_SIGNING_PUBLIC_KEY"'));
});

test('backup installs and checks the PGDG PostgreSQL 17 client before dumping', () => {
  assert.match(backup, /apt\.postgresql\.org\/pub\/repos\/apt/);
  assert.match(backup, /B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8/);
  assert.match(backup, /apt-get install -y postgresql-client-17/);
  assert.match(backup, /PGBIN=\/usr\/lib\/postgresql\/17\/bin/);
  assert.match(backup, /PG_DUMP="\$PGBIN\/pg_dump"/);
  assert.match(backup, /\[ ! -x "\$PG_DUMP" \]/);
  assert.match(backup, /ls -l \/usr\/lib\/postgresql\/\*\/bin\/pg_dump/);
  assert.match(backup, /"\$PG_DUMP" --version/);
  assert.match(backup, /"\$PG_DUMP" --version \| grep -E/);
  assert.match(backup, /echo "\$PGBIN" >> "\$GITHUB_PATH"/);
  assert.match(backup, /echo "PG_DUMP=\$PG_DUMP" >> "\$GITHUB_ENV"/);
  assert.ok(backup.indexOf('- name: Install PostgreSQL 17 client') < backup.indexOf('- name: Dump database'));
  assert.match(backup, /PGDATABASE: \$\{\{ secrets\.BACKUP_DATABASE_URL \}\}/);
  assert.match(backup, /"\$PG_DUMP" --dbname "\$PGDATABASE" --no-owner --no-acl/);
});

test('backup uses a restorable data-only public and auth dump', () => {
  assert.match(backup, /"\$PG_DUMP" --dbname "\$PGDATABASE" --no-owner --no-acl --data-only --schema=public --schema=auth/);
  assert.match(backup, /--exclude-table-data=auth\.schema_migrations/);
  assert.doesNotMatch(backup, /"\$PG_DUMP" --dbname "\$PGDATABASE" --no-owner --no-acl --file/);
  assert.match(backup, /PGDATABASE: \$\{\{ secrets\.BACKUP_DATABASE_URL \}\}/);
});

test('backup uses B2 path-style and phase-isolated credentials', () => {
  assert.match(backup, /https:\/\/s3\.us-east-005\.backblazeb2\.com/);
  assert.match(backup, /addressing_style = path/);
  assert.match(backup, /AWS_DEFAULT_REGION: \$\{\{ vars\.AWS_DEFAULT_REGION \|\| 'us-east-005' \}\}/);
  assert.match(backup, /BACKUP_DAILY_RETENTION/);
  assert.match(backup, /BACKUP_WEEKLY_RETENTION/);
  assert.match(backup, /secrets\.BACKUP_S3_ACCESS_KEY_ID/);
  assert.match(backup, /secrets\.BACKUP_SIGNING_PRIVATE_KEY/);
  assert.match(ci, /BACKUP_DOCKER_TEST=1 python3 -m unittest discover -s scripts\/backup -v/);
});
