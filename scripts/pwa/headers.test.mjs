import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const headers = await readFile(new URL('../../web/_headers', import.meta.url), 'utf8');
const rules = new Map();
let current;
for (const line of headers.split('\n')) {
  if (!line.trim()) continue;
  if (!line.startsWith(' ')) {current = new Map(); rules.set(line, current);}
  else {
    const separator = line.indexOf(':');
    current.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
  }
}

test('unfingerprinted entry points always revalidate, credential routes never store', () => {
  for (const path of ['/index.html', '/flutter_bootstrap.js', '/main.dart.js',
    '/flutter_service_worker.js', '/version.json']) {
    assert.equal(rules.get(path).get('Cache-Control'), 'no-cache', path);
  }
  assert.equal(rules.get('/invite/*').get('Cache-Control'), 'no-store');
  assert.equal(rules.get('/set-password').get('Cache-Control'), 'no-store');
  assert.ok(!headers.includes('immutable'));
});

test('global security headers exist; CSP stays report-only', () => {
  const global = rules.get('/*');
  assert.equal(global.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(global.get('Referrer-Policy'), 'no-referrer');
  assert.equal(global.get('Strict-Transport-Security'), 'max-age=31536000');
  assert.ok(global.has('Permissions-Policy'));
  assert.ok(global.has('Content-Security-Policy-Report-Only'));
  assert.ok(!global.has('Content-Security-Policy'));
});
