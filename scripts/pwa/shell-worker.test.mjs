import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile, mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import vm from 'node:vm';
import {generate, isShellAsset} from '../generate-shell-worker.mjs';

const template = await readFile(new URL('./shell-worker.js', import.meta.url), 'utf8');
function worker() {
  const handlers = {};
  const deleted = [];
  const writes = [];
  const fetches = [];
  const cached = new Map();
  const cache = {put: async (key, value) => {writes.push(key); cached.set(key, value);},
    match: async key => cached.get(key)};
  const context = vm.createContext({URL, Request, Set,
    self: {registration: {scope: 'https://app.test/'},
      addEventListener: (type, callback) => {handlers[type] = callback;}},
    caches: {open: async () => cache,
      keys: async () => ['educador-static-shell-old', 'educador-static-shell-v1',
        'flutter-app-cache', 'other-app'],
      delete: async name => deleted.push(name)},
    fetch: async request => {fetches.push(request); return {ok: true, type: 'basic'};},
  });
  vm.runInContext(template.replace('__VERSION__', '"v1"')
    .replace('__ASSETS__', '["index.html","main.dart.js"]'), context);
  return {context, handlers, deleted, writes, fetches, cached};
}
function route(w, url, options = {}) {
  w.context.request = {url, method: 'GET', mode: 'cors', headers: new Headers(), ...options};
  return vm.runInContext('route(request)', w.context);
}

test('exact static allowlist; APIs, signed/query/fragment URLs, credentials and writes bypass', () => {
  const w = worker();
  assert.equal(route(w, 'https://app.test/main.dart.js'), 'https://app.test/main.dart.js');
  for (const url of ['https://supabase.test/main.dart.js', 'https://app.test/rest/v1/profiles',
    'https://app.test/auth/v1/user', 'https://app.test/lessons/audio.mp3',
    'https://app.test/main.dart.js?token=fake', 'https://app.test/main.dart.js#fake',
    'https://app.test/invite/accept?token=fake', 'https://app.test/set-password']) {
    assert.equal(route(w, url), null, url);
  }
  for (const options of [{method: 'POST'}, {headers: new Headers({Authorization: 'Bearer fake'})},
    {headers: new Headers({Range: 'bytes=0-10'})}]) {
    assert.equal(route(w, 'https://app.test/main.dart.js', options), null);
  }
});

test('every navigation including bearer links uses only sanitized index key', async () => {
  const w = worker();
  w.cached.set('https://app.test/index.html', 'public index');
  for (const path of ['/contexts', '/invite/accept?token=fake', '/set-password#access_token=fake']) {
    assert.equal(route(w, 'https://app.test' + path, {mode: 'navigate'}), 'https://app.test/index.html');
    let response;
    w.handlers.fetch({request: {url: 'https://app.test' + path, method: 'GET',
      mode: 'navigate', headers: new Headers()}, respondWith: promise => {response = promise;}});
    assert.equal(await response, 'public index');
  }
  assert.equal(w.fetches.length, 0);
  assert.equal(w.writes.length, 0);
});

test('installation fetches only public manifest files without cookies, activation cleans owned caches', async () => {
  const w = worker();
  let pending;
  w.handlers.install({waitUntil: promise => {pending = promise;}});
  await pending;
  assert.deepEqual(w.writes, ['https://app.test/index.html', 'https://app.test/main.dart.js']);
  assert.ok(w.fetches.every(request => request.credentials === 'omit' && request.redirect === 'error'));
  w.handlers.activate({waitUntil: promise => {pending = promise;}});
  await pending;
  assert.deepEqual(w.deleted, ['educador-static-shell-old', 'flutter-app-cache']);
  assert.ok(!template.includes('skipWaiting('));
  assert.ok(!template.includes('clients.claim('));
});

test('failed install deletes incomplete cache and does not activate', async () => {
  const w = worker();
  w.context.fetch = async () => ({ok: false, type: 'basic'});
  let pending;
  w.handlers.install({waitUntil: promise => {pending = promise;}});
  await assert.rejects(pending, /Shell install failed/);
  assert.deepEqual(w.deleted, ['educador-static-shell-v1']);
});

test('missing navigation entry fetches sanitized public index anonymously', async () => {
  const w = worker();
  let response;
  w.handlers.fetch({request: {url: 'https://app.test/set-password?code=fake',
    method: 'GET', mode: 'navigate', headers: new Headers()},
    respondWith: promise => {response = promise;}});
  await response;
  assert.equal(w.fetches[0].url, 'https://app.test/index.html');
  assert.equal(w.fetches[0].credentials, 'omit');
  assert.equal(w.writes.length, 0);
});

test('unhandled API requests never call respondWith or write cache', () => {
  const w = worker();
  w.handlers.fetch({request: new Request('https://app.test/rest/v1/profiles'),
    respondWith: () => assert.fail('API intercepted')});
  assert.equal(w.writes.length, 0);
});

test('generator is deterministic and changes version for asset changes', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'educador-shell-'));
  try {
    for (const path of ['index.html', 'main.dart.js', 'flutter_bootstrap.js']) {
      await writeFile(join(dir, path), path);
    }
    await mkdir(join(dir, 'assets'));
    await writeFile(join(dir, 'assets/font.ttf'), 'font');
    await writeFile(join(dir, 'private.json'), 'not a shell asset');
    const first = await generate(dir);
    assert.deepEqual((await generate(dir)), first);
    assert.ok(!first.files.includes('private.json'));
    await writeFile(join(dir, 'assets/font.ttf'), 'new font');
    assert.notEqual((await generate(dir)).version, first.version);
    await writeFile(join(dir, 'flutter_bootstrap.js'),
      "_flutter.loader.load({serviceWorkerSettings: {serviceWorkerVersion: '1'}});");
    await assert.rejects(generate(dir), /web\/flutter_bootstrap\.js/);
    await writeFile(join(dir, 'flutter_bootstrap.js'), 'flutter_bootstrap.js');
    assert.equal(isShellAsset('flutter_service_worker.js'), false);
    assert.equal(isShellAsset('assets/debug.map'), false);
  } finally {await rm(dir, {recursive: true, force: true});}
});
