import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const backup = readFileSync(new URL('../.github/workflows/backup.yml', import.meta.url), 'utf8');
const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');

test('backup has a daily schedule and confirmed manual dispatch but remains hard-disabled', () => {
  assert.match(backup, /^  schedule:\n    - cron: '17 3 \* \* \*'$/m);
  assert.match(backup, /^  workflow_dispatch:\n    inputs:\n      confirm:\n        description: [^\n]+\n        type: boolean\n        required: true\n        default: false$/m);
  assert.match(backup, /false && github\.ref/);
  assert.match(backup, /github\.event_name == 'schedule' \|\| inputs\.confirm == true/);
});

test('backup installs and checks the PGDG PostgreSQL 17 client before dumping', () => {
  assert.match(backup, /apt\.postgresql\.org\/pub\/repos\/apt/);
  assert.match(backup, /B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8/);
  assert.match(backup, /apt-get install -y postgresql-client-17/);
  assert.match(backup, /pg_dump --version \| grep -E/);
  assert.ok(backup.indexOf('- name: Install PostgreSQL 17 client') < backup.indexOf('- name: Dump database'));
  assert.match(backup, /PGDATABASE: \$\{\{ secrets\.BACKUP_DATABASE_URL \}\}/);
  assert.match(backup, /pg_dump --no-owner --no-acl/);
});

test('backup uses a restorable data-only public and auth dump', () => {
  assert.match(backup, /pg_dump --no-owner --no-acl --data-only --schema=public --schema=auth/);
  assert.match(backup, /--exclude-table-data=auth\.schema_migrations/);
  assert.doesNotMatch(backup, /pg_dump --no-owner --no-acl --file/);
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
