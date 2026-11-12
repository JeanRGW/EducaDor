import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const backup = readFileSync(new URL('../.github/workflows/backup.yml', import.meta.url), 'utf8');
const dumpStep = backup.slice(backup.indexOf('- name: Dump database'),
                              backup.indexOf('- name: Encrypt and sign'));

test('dump step captures stderr instead of discarding it', () => {
  assert.ok(dumpStep.length > 0, 'Dump database step is missing');
  assert.doesNotMatch(dumpStep, /2>\/dev\/null/);
  assert.match(dumpStep, /errors="\$work\/pg\.err"/);
  assert.match(dumpStep, /2>"\$errors"/);
  assert.match(dumpStep, /umask 077/);
});

test('dump step preserves stdout/exit handling', () => {
  assert.match(dumpStep, /set -euo pipefail/);
  assert.match(dumpStep, /--file "\$work\/dump\.sql"/);
  assert.match(dumpStep, /status=\$\?/);
  assert.match(dumpStep, /if \[ "\$status" -ne 0 \]; then/);
  assert.match(dumpStep, /exit 1/);
  assert.ok(dumpStep.indexOf('exit 1') > dumpStep.indexOf('redact.py'),
            'the step must exit non-zero after printing the diagnostic');
});

test('dump step prints only the redacted, bounded diagnostic', () => {
  assert.match(dumpStep, /python3 scripts\/backup\/redact\.py "\$errors"/);
  assert.doesNotMatch(dumpStep, /cat "\$errors"/);
  assert.doesNotMatch(dumpStep, /echo "\$PGDATABASE"/);
  assert.doesNotMatch(dumpStep, /printenv/);
});

test('redaction helper removes secrets, URL passwords and bounds output', () => {
  const helper = readFileSync(new URL('../scripts/backup/redact.py', import.meta.url), 'utf8');
  assert.match(helper, /DIAGNOSTIC_LIMIT = 4096/);
  assert.match(helper, /name == 'PGDATABASE' or name\.startswith\('BACKUP_'\)/);
  assert.match(helper, /postgres\(\?:ql\)\?:\/\//);
  assert.match(helper, /sslmode=require/);
  assert.match(helper, /IPv6/);
});
