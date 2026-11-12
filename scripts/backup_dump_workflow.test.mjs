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

test('dump step validates the connection URL before invoking pg_dump', () => {
  const check = dumpStep.indexOf('scripts/backup/check_db_url.py');
  const dump = dumpStep.indexOf('"$PG_DUMP" --dbname "$PGDATABASE"');
  assert.ok(check > 0, 'the URL validation helper is missing from the dump step');
  assert.ok(dump > check, 'pg_dump must only run after URL validation');
  assert.match(dumpStep, /PGDATABASE="\$PGDATABASE" (?:BACKUP_EXPECTED_PROJECT_REF="[^"]*" )?python3 scripts\/backup\/check_db_url\.py/);
  assert.doesNotMatch(dumpStep, /check_db_url\.py[^\n]*\|\| true/);
});

test('dump step compares the derived project ref with an optional variable', () => {
  assert.match(dumpStep,
               /^          BACKUP_EXPECTED_PROJECT_REF: \$\{\{ vars\.BACKUP_EXPECTED_PROJECT_REF \}\}$/m);
  assert.match(dumpStep, /BACKUP_EXPECTED_PROJECT_REF="\$\{BACKUP_EXPECTED_PROJECT_REF:-\}"/);
  assert.doesNotMatch(dumpStep, /vars\.BACKUP_EXPECTED_PROJECT_REF \|\|/,
                      'no default ref: when the variable is unset the check is skipped');
  const wiring = backup.split('\n').filter((line) => line.trim().startsWith('BACKUP_EXPECTED_PROJECT_REF:'));
  assert.equal(wiring.length, 1, 'the expected ref is wired only into the dump step');
  assert.ok(dumpStep.includes(wiring[0]), 'the variable must be scoped to the dump step');
});

test('dump step passes the URL explicitly and never positionally', () => {
  const invocation = dumpStep.match(/"\$PG_DUMP" ([^\n]*)/);
  assert.ok(invocation, 'the pg_dump invocation is missing');
  assert.match(invocation[1], /^--dbname "\$PGDATABASE" --no-owner --no-acl/);
  assert.doesNotMatch(dumpStep, /"\$PG_DUMP"\s+"\$PGDATABASE"/);
  assert.doesNotMatch(dumpStep, /echo[^\n]*PGDATABASE|printf[^\n]*PGDATABASE/);
  assert.doesNotMatch(dumpStep, /set -x/);
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
