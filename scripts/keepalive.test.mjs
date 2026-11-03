import assert from 'node:assert/strict';
import test from 'node:test';
import { keepalive } from './keepalive.mjs';

const config = { url: 'https://example.supabase.co', serviceRoleKey: 'test-server-key' };

test('reads a bounded real table with server authentication, no redirects', async () => {
  await keepalive({ ...config, fetchImpl: async (target, options) => {
    assert.equal(String(target), 'https://example.supabase.co/rest/v1/profiles?select=id&limit=1');
    assert.equal(options.method, 'GET');
    assert.equal(options.headers.apikey, config.serviceRoleKey);
    assert.equal(options.headers.Authorization, `Bearer ${config.serviceRoleKey}`);
    assert.equal(options.redirect, 'error');
    assert.ok(options.signal instanceof AbortSignal);
    return Response.json([{ id: 'mock-profile' }]);
  } });
});

test('empty table still proves the database query completed', async () => {
  await keepalive({ ...config, fetchImpl: async () => Response.json([]) });
});

test('missing credentials and unsafe origins fail before a request', async () => {
  for (const overrides of [{ serviceRoleKey: '' }, { url: '' }, { url: 'http://example.com' },
    { url: 'invalid' }, { url: 'https://user:password@example.com' },
    { url: 'https://example.com/path' }, { url: 'https://example.com/?secret=x' }]) {
    await assert.rejects(keepalive({ ...config, ...overrides, fetchImpl: () => {
      assert.fail('must not request');
    } }), /Set SUPABASE|HTTPS origin/);
  }
});

test('HTTP errors do not expose response bodies or credentials', async () => {
  for (const status of [301, 401, 403, 404, 429, 500, 503]) {
    await assert.rejects(keepalive({ ...config, fetchImpl: async () =>
      new Response('private response body', { status }) }),
    (error) => error.message.includes(`HTTP ${status}`) &&
      !error.message.includes('private') && !error.message.includes(config.serviceRoleKey));
  }
});

test('rejects malformed success bodies and suppresses network diagnostics', async () => {
  for (const body of ['not json', '{}', '[{"unexpected":true}]', '[{"id":"1"},{"id":"2"}]']) {
    await assert.rejects(keepalive({ ...config, fetchImpl: async () => new Response(body) }),
      /invalid JSON|unexpected table response/);
  }
  await assert.rejects(keepalive({ ...config, fetchImpl: async () => {
    throw new Error(config.serviceRoleKey);
  } }), { message: 'Database keepalive request failed (network, redirect, or timeout).' });
});
