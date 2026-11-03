import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const workflow = (name) => readFileSync(new URL(`../.github/workflows/${name}.yml`, import.meta.url), 'utf8');

test('operations remain manual-only, main-only and environment-gated', () => {
  for (const [name, environment] of [['deploy-pages', 'pages-production'], ['keepalive', 'database-keepalive']]) {
    const text = workflow(name);
    const triggers = text.split('\non:\n')[1].split('\npermissions:')[0];
    assert.equal(triggers.trim(), 'workflow_dispatch:');
    assert.match(text, /if: github.ref == 'refs\/heads\/main'/);
    assert.ok(text.includes(`environment: ${environment}`));
    assert.match(text, /cancel-in-progress: false/);
    assert.doesNotMatch(text, /pull_request_target|secrets: inherit/);
  }
});

test('CI validates app and all function suites without deployment credentials', () => {
  const text = workflow('ci');
  for (const command of ['flutter analyze --no-pub', 'flutter test --no-pub',
    'flutter build web --release', '--pwa-strategy offline-first',
    '--dart-define-from-file=config/staging.public.json',
    'node --test scripts/*test.mjs supabase/tests/*.test.mjs', 'deno test supabase/functions/']) {
    assert.ok(text.includes(command), command);
  }
  assert.doesNotMatch(text, /secrets\.|wrangler|--allow-all/);
  assert.match(text, /pull_request:/);
  assert.match(text, /flutter-version: '3\.47\.5'/);
});

test('operations use only scoped credentials and fixed deployment target', () => {
  const pages = workflow('deploy-pages');
  assert.match(pages, /secrets\.CLOUDFLARE_API_TOKEN/);
  assert.ok(pages.includes('wrangler@4.157.0 pages deploy build/web --project-name=educador --branch=main'));
  const keepalive = workflow('keepalive');
  assert.match(keepalive, /vars\.SUPABASE_URL/);
  assert.match(keepalive, /secrets\.SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(keepalive, /run: node scripts\/keepalive\.mjs/);
  assert.doesNotMatch(keepalive, /ANON_KEY|PASSWORD|curl|--verbose/);
});

test('new workflows pin actions, bound runtime and use read-only repository permissions', () => {
  for (const name of ['ci', 'deploy-pages', 'keepalive']) {
    const text = workflow(name);
    assert.match(text, /permissions:\n  contents: read/);
    assert.match(text, /timeout-minutes: \d+/);
    for (const match of text.matchAll(/uses: (.+)/g)) {
      assert.match(match[1], /@[a-f0-9]{40}(?: |$)/);
    }
  }
  assert.match(workflow('database'), /timeout-minutes: 20/);
  assert.match(workflow('database'), /concurrency:/);
});
