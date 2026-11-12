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
