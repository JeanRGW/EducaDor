import { admin, caller, preflight, respond, tokenHash } from '../_shared/invites.ts';

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  const current = await caller(req);
  if (!current) return respond(req, { error: 'Authentication required' }, 401);
  try {
    const { token } = await req.json();
    if (typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) {
      return respond(req, { error: 'Invalid invitation' }, 400);
    }
    // Verified identity only; the transaction derives role/company from the
    // invitation and serializes with revocation before granting access.
    const { error } = await admin.rpc('accept_membership_invite', {
      p_token_hash: await tokenHash(token), p_user: current.id, p_email: current.email,
    });
    if (error) return respond(req, { error: 'Invitation unavailable' }, 400);
    return respond(req, { success: true });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
