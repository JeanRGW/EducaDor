import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.116.0';

const url = Deno.env.get('SUPABASE_URL')!;
const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

export const admin = createClient(url, secret, {
  auth: { autoRefreshToken: false, persistSession: false },
});

export function respond(req: Request, body: unknown, status = 200): Response {
  const origin = req.headers.get('origin');
  const allowed = (Deno.env.get('ALLOWED_APP_ORIGINS') ??
    Deno.env.get('APP_ORIGIN') ?? '').split(',').map((value) => value.trim());
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      ...(origin && allowed.includes(origin)
        ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
          'Access-Control-Allow-Methods': 'POST, OPTIONS' }
        : {}),
    },
  });
}

export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') return respond(req, {}, 204);
  const origin = req.headers.get('origin');
  const allowed = (Deno.env.get('ALLOWED_APP_ORIGINS') ??
    Deno.env.get('APP_ORIGIN') ?? '').split(',').map((value) => value.trim());
  if (req.method !== 'POST' || (origin && !allowed.includes(origin))) {
    return respond(req, { error: 'Forbidden' }, 403);
  }
  return null;
}

export async function caller(req: Request): Promise<{
  id: string; email: string; client: SupabaseClient;
} | null> {
  const jwt = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user?.id || !data.user.email || !data.user.email_confirmed_at) {
    return null;
  }
  const client = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  return { id: data.user.id, email: data.user.email.toLowerCase(), client };
}

export function newToken(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)),
    (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export async function tokenHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, '0')).join('');
}
