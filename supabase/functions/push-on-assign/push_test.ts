import { handle, parseEvent, type Dependencies } from './handler.ts';
import { createSender } from './fcm.ts';
const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
function assert(value: unknown, message = 'assertion failed'): asserts value { if (!value) throw Error(message); }
const request = (body: unknown) => new Request('https://example.test', { method: 'POST', body: JSON.stringify(body) });
Deno.test('strict events, authentication, claim denial and partial send', async () => {
  for (const invalid of [{ event: 'course_available', course_id: id, token: 'secret' },
    { event: 'certificate_issued', certificate_id: id, url: 'https://evil' }]) {
    let threw = false; try { parseEvent(invalid); } catch { threw = true; } assert(threw);
  }
  const event = { event: 'course_available', course_id: id };
  const tokens = ['one', 'two', 'three'].map((token) => ({ user_id: id, token, updated_at: 'time' }));
  const cleaned: string[] = [];
  const deps: Dependencies = { authenticate: async () => async () => ({ suppressed: false, tokens, course_id: id }),
    send: async (token) => token === 'one' ? 'sent' : token === 'two' ? 'invalid' : 'failed',
    cleanup: async (token) => { cleaned.push(token.token); } };
  const result = await handle(request(event), deps);
  assert(JSON.stringify(result.body) === JSON.stringify({ event: event.event, sent: 1, failed: 2, truncated: false, suppressed: false }));
  assert(cleaned.join() === 'two');
  assert((await handle(request(event), { ...deps, authenticate: async () => null })).status === 401);
  assert((await handle(request(event), { ...deps, authenticate: async () => async () => { throw Error('forbidden'); } })).status === 403);
  assert((await handle(request({ ...event, token: 'bad' }), deps)).status === 400);
});
Deno.test('bounded concurrency and recipient limit', async () => {
  let active = 0, max = 0, calls = 0;
  const tokens = Array.from({ length: 101 }, (_, i) => ({ user_id: id, token: String(i), updated_at: 't' }));
  const result = await handle(request({ event: 'course_available', course_id: id }), {
    authenticate: async () => async () => ({ suppressed: false, tokens, course_id: id }),
    send: async () => { active++; max = Math.max(max, active); await Promise.resolve(); active--; calls++; return 'sent'; },
    cleanup: async () => {} });
  assert(calls === 100 && max <= 5 && (result.body as { truncated: boolean }).truncated);
});
Deno.test('FCM signs OAuth and only cleans up explicit UNREGISTERED', async () => {
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let binary = ''; for (const b of pkcs8) binary += String.fromCharCode(b);
  const account = JSON.stringify({ project_id: 'test-project', client_email: 'test@example.test',
    private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----` });
  let calls = 0;
  const fetcher: typeof fetch = async (input, init) => {
    calls++;
    if (String(input).includes('oauth2')) {
      const assertion = new URLSearchParams(init?.body as string).get('assertion')!;
      const [header, claims, signature] = assertion.split('.');
      const decode = (s: string) => Uint8Array.from(atob(s.replaceAll('-', '+').replaceAll('_', '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), (c) => c.charCodeAt(0));
      assert(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pair.publicKey, decode(signature), new TextEncoder().encode(`${header}.${claims}`)));
      return Response.json({ access_token: 'oauth-token' });
    }
    const payload = JSON.parse(init!.body as string);
    assert(payload.message.data.event === 'certificate_issued' && payload.message.data.course_id === id);
    assert(!('url' in payload.message.data));
    return Response.json({ error: { details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }, { status: 404 });
  };
  const send = createSender(account, fetcher);
  assert(await send('private-token', { event: 'certificate_issued', certificate_id: id }, id) === 'invalid');
  assert(calls === 2);
});
