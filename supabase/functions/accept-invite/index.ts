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
    const { data: invite } = await admin.from('membership_invites').select('*')
      .eq('token_hash', await tokenHash(token)).eq('email', current.email)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle();
    if (!invite) return respond(req, { error: 'Invitation unavailable' }, 400);
    if (invite.company_id) {
      const { data: company } = await admin.from('companies').select('id')
        .eq('id', invite.company_id).eq('active', true).maybeSingle();
      if (!company) return respond(req, { error: 'Company unavailable' }, 400);
    }
    // Auth identity is verified above. Roles and company always come from the
    // server-side invitation row, never from client input or user_metadata.
    const result = invite.role === 'gestor'
      ? await admin.from('platform_gestors').upsert({ user_id: current.id })
      : await admin.from('company_memberships').upsert({
          user_id: current.id, company_id: invite.company_id, role: invite.role,
          dept: invite.dept, job_title: invite.job_title,
        }, { onConflict: 'user_id,company_id,role' });
    if (result.error) return respond(req, { error: 'Could not activate access' }, 500);
    const { error } = await admin.from('membership_invites')
      .delete().eq('id', invite.id);
    if (error) return respond(req, { error: 'Could not finish invitation' }, 500);
    return respond(req, { success: true });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
