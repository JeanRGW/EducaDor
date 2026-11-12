import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const backup = readFileSync(new URL('../.github/workflows/backup.yml', import.meta.url), 'utf8');
const ci = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');

test('backup remains disabled, manual, B2 path-style and phase-isolated', () => {
  assert.match(backup, /false && github\.ref/);
  assert.doesNotMatch(backup, /^\s+schedule:/m);
  assert.match(backup, /https:\/\/s3\.us-east-005\.backblazeb2\.com/);
  assert.match(backup, /addressing_style = path/);
  assert.match(backup, /BACKUP_DAILY_RETENTION/);
  assert.match(backup, /BACKUP_WEEKLY_RETENTION/);
  assert.match(backup, /secrets\.BACKUP_S3_ACCESS_KEY_ID/);
  assert.match(backup, /secrets\.BACKUP_SIGNING_PRIVATE_KEY/);
  assert.match(ci, /BACKUP_DOCKER_TEST=1 python3 -m unittest discover -s scripts\/backup -v/);
});
