import { pathToFileURL } from 'node:url';

// This is a real PostgREST table read, not an Auth/API health ping.
export async function keepalive({ url, serviceRoleKey, fetchImpl = fetch }) {
  if (!url || !serviceRoleKey?.trim()) {
    throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the protected environment.');
  }
  let base;
  try {
    base = new URL(url);
  } catch {
    throw new Error('SUPABASE_URL must be a project HTTPS origin.');
  }
  if (base.protocol !== 'https:' || base.username || base.password ||
      base.pathname !== '/' || base.search || base.hash) {
    throw new Error('SUPABASE_URL must be a project HTTPS origin.');
  }
  const target = new URL('/rest/v1/profiles?select=id&limit=1', base);
  let response;
  try {
    response = await fetchImpl(target, {
      method: 'GET',
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Accept: 'application/json',
      },
      redirect: 'error',
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new Error('Database keepalive request failed (network, redirect, or timeout).');
  }
  if (response.status !== 200) {
    throw new Error(`Database keepalive failed with HTTP ${response.status}. Check environment credentials and project availability.`);
  }
  let rows;
  try {
    rows = await response.json();
  } catch {
    throw new Error('Database keepalive returned invalid JSON.');
  }
  if (!Array.isArray(rows) || rows.length > 1 ||
      rows.some((row) => !row || typeof row.id !== 'string')) {
    throw new Error('Database keepalive returned an unexpected table response.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await keepalive({
      url: process.env.SUPABASE_URL,
      serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    });
    console.log('Database keepalive table read succeeded.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
