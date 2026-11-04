import type { PushEvent } from './handler.ts';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
const encoder = new TextEncoder();
function base64url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
function encoded(value: unknown): string { return base64url(encoder.encode(JSON.stringify(value))); }
export function createSender(raw: string, fetcher: typeof fetch = fetch) {
  const account = JSON.parse(raw) as ServiceAccount;
  if (!account.project_id || !/^[a-z0-9][a-z0-9-]{4,62}$/.test(account.project_id) ||
      !account.client_email || !account.private_key) throw Error('Invalid configuration');
  let access: Promise<string> | undefined;
  async function authorize(): Promise<string> {
    const pem = account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
    const binary = atob(pem);
    const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(binary, (c) => c.charCodeAt(0)),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
    const now = Math.floor(Date.now() / 1000);
    const unsigned = `${encoded({ alg: 'RS256', typ: 'JWT' })}.${encoded({ iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token',
      iat: now, exp: now + 3600 })}`;
    const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned));
    const response = await fetcher('https://oauth2.googleapis.com/token', { method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' }, signal: AbortSignal.timeout(8000),
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${unsigned}.${base64url(new Uint8Array(signature))}` }) });
    if (!response.ok) throw Error('OAuth failed');
    const body = await response.json();
    if (typeof body.access_token !== 'string' || !body.access_token) throw Error('OAuth failed');
    return body.access_token;
  }
  return async (token: string, event: PushEvent, courseId: string): Promise<'sent' | 'invalid' | 'failed'> => {
    access ??= authorize();
    const bearer = await access;
    const data: Record<string, string> = { event: event.event, course_id: courseId };
    if (event.event === 'course_available' && event.company_id) data.company_id = event.company_id;
    if (event.event === 'certificate_issued') data.certificate_id = event.certificate_id;
    const response = await fetcher(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: 'POST', signal: AbortSignal.timeout(8000), headers: { authorization: `Bearer ${bearer}`,
        'content-type': 'application/json' }, body: JSON.stringify({ message: { token, data,
        notification: event.event === 'course_available'
          ? { title: 'Nova trilha disponível', body: 'Uma trilha está disponível para você.' }
          : { title: 'Certificado disponível', body: 'Seu certificado está disponível.' } } }) });
    if (response.ok) return 'sent';
    let error: unknown;
    try { error = await response.json(); } catch { return 'failed'; }
    const details = (error as { error?: { details?: Array<{ '@type'?: string; errorCode?: string }> } })?.error?.details;
    return response.status === 404 && Array.isArray(details) && details.some((d) =>
      d['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError' && d.errorCode === 'UNREGISTERED')
      ? 'invalid' : 'failed';
  };
}
