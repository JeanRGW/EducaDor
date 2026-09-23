import { admin, caller, newToken, preflight, respond, tokenHash } from '../_shared/invites.ts';

type CompanyInput = Record<'name' | 'cnpj' | 'responsible' | 'email' |
  'phone' | 'address' | 'city' | 'state' | 'field', string>;

Deno.serve(async (req) => {
  const blocked = preflight(req);
  if (blocked) return blocked;
  const current = await caller(req);
  if (!current) return respond(req, { error: 'Authentication required' }, 401);

  try {
    const input = await req.json();
    const role = input.role as string;
    const name = (input.name as string | undefined)?.trim();
    const email = (input.email as string | undefined)?.trim().toLowerCase();
    if (!['gestor', 'empresa', 'funcionario'].includes(role) ||
      !name || name.length > 200 || !email || email.length > 320 ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return respond(req, { error: 'Invalid invitation' }, 400);
    }
    const { data: selected, error: contextError } =
      await current.client.rpc('selected_context');
    if (contextError || !selected?.length) return respond(req, { error: 'Select a profile' }, 403);
    const context = selected[0] as { role: string; company_id: string | null };
    if (context.role !== 'gestor' &&
      !(context.role === 'empresa' && role !== 'gestor' && !input.company &&
        input.companyId === context.company_id)) {
      return respond(req, { error: 'Forbidden' }, 403);
    }

    const appOrigin = Deno.env.get('APP_ORIGIN');
    if (!appOrigin) return respond(req, { error: 'Invitation origin not configured' }, 503);
    let companyId: string | null = role === 'gestor' ? null : input.companyId ?? null;
    if (companyId && !/^[0-9a-fA-F-]{36}$/.test(companyId)) {
      return respond(req, { error: 'Invalid company' }, 400);
    }
    let createdCompany = false;
    if (input.company) {
      if (context.role !== 'gestor' || role !== 'empresa' || companyId) {
        return respond(req, { error: 'Forbidden' }, 403);
      }
      const company = input.company as Partial<CompanyInput>;
      if (typeof company.name !== 'string' || !company.name.trim() ||
        company.name.length > 200) return respond(req, { error: 'Invalid company' }, 400);
      const { data, error } = await admin.from('companies').insert({
        name: company.name.trim(), cnpj: company.cnpj?.trim() || null,
        responsible: company.responsible?.trim() || null,
        email: company.email?.trim() || null, phone: company.phone?.trim() || null,
        address: company.address?.trim() || null, city: company.city?.trim() || null,
        state: company.state?.trim() || null, field: company.field?.trim() || null,
      }).select('id').single();
      if (error) return respond(req, { error: 'Could not create company' }, 400);
      companyId = data.id as string;
      createdCompany = true;
    }
    if (role !== 'gestor') {
      if (!companyId) return respond(req, { error: 'Company required' }, 400);
      const { data: company } = await admin.from('companies')
        .select('id').eq('id', companyId).eq('active', true).maybeSingle();
      if (!company) return respond(req, { error: 'Company unavailable' }, 400);
    }

    const { data: existing } = await admin.from('profiles')
      .select('id').ilike('email', email).maybeSingle();
    if (existing) {
      const { data: grant } = role === 'gestor'
        ? await admin.from('platform_gestors').select('user_id').eq('user_id', existing.id).maybeSingle()
        : await admin.from('company_memberships').select('user_id')
          .eq('user_id', existing.id).eq('company_id', companyId!).eq('role', role).maybeSingle();
      if (grant) return respond(req, { error: 'Access already exists' }, 409);
    }
    let expiredQuery = admin.from('membership_invites').delete()
      .eq('email', email).eq('role', role)
      .lt('expires_at', new Date().toISOString());
    expiredQuery = companyId === null
      ? expiredQuery.is('company_id', null)
      : expiredQuery.eq('company_id', companyId);
    await expiredQuery;
    let pendingQuery = admin.from('membership_invites').select('id')
      .eq('email', email).eq('role', role)
      .gt('expires_at', new Date().toISOString());
    pendingQuery = companyId === null
      ? pendingQuery.is('company_id', null)
      : pendingQuery.eq('company_id', companyId);
    const { data: pending } = await pendingQuery.limit(1);
    if (pending?.length) return respond(req, { error: 'Invitation already pending' }, 409);

    const token = newToken();
    const target = `${appOrigin.replace(/\/$/, '')}/invite/accept?token=${token}`;
    const { data: invitation, error: insertError } = await admin.from('membership_invites')
      .insert({ email, role, company_id: companyId, invited_by: current.id,
        dept: role === 'funcionario' && typeof input.department === 'string'
          ? input.department.trim().slice(0, 100) : null,
        job_title: role === 'funcionario' && typeof input.jobTitle === 'string'
          ? input.jobTitle.trim().slice(0, 100) : null,
        token_hash: await tokenHash(token),
        expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString() })
      .select('id').single();
    if (insertError) {
      if (createdCompany) await admin.from('companies').delete().eq('id', companyId!);
      return respond(req, { error: 'Could not create invitation' }, 400);
    }

    if (existing) {
      const { data: account, error: accountError } =
        await admin.auth.admin.getUserById(existing.id);
      if (accountError || !account.user) {
        await admin.from('membership_invites').delete().eq('id', invitation.id);
        if (createdCompany) await admin.from('companies').delete().eq('id', companyId!);
        return respond(req, { error: 'Account unavailable' }, 400);
      }
      if (account.user.email_confirmed_at) return respond(req, { link: target });
      // An expired first invitation leaves an unconfirmed Auth account.
      // GoTrue may reject a second invite for an existing account; an
      // admin-generated sign-in link lets its owner confirm the same email.
      const { data: resend, error: resendError } = await admin.auth.admin.generateLink({
        type: 'magiclink', email, options: { redirectTo: target },
      });
      if (resendError || resend.user?.id !== existing.id ||
        !resend.properties?.action_link) {
        await admin.from('membership_invites').delete().eq('id', invitation.id);
        if (createdCompany) await admin.from('companies').delete().eq('id', companyId!);
        return respond(req, { error: 'Could not reissue account link' }, 400);
      }
      return respond(req, { link: resend.properties.action_link });
    }
    const { data: generated, error: linkError } = await admin.auth.admin.generateLink({
      type: 'invite', email, options: { redirectTo: target },
    });
    if (linkError || !generated.user || !generated.properties?.action_link) {
      await admin.from('membership_invites').delete().eq('id', invitation.id);
      if (createdCompany) await admin.from('companies').delete().eq('id', companyId!);
      return respond(req, { error: 'Could not create account link' }, 400);
    }
    const { error: profileError } = await admin.from('profiles').insert({
      id: generated.user.id, full_name: name, email, needs_password: true,
    });
    if (profileError) {
      await admin.from('membership_invites').delete().eq('id', invitation.id);
      if (createdCompany) await admin.from('companies').delete().eq('id', companyId!);
      return respond(req, { error: 'Could not create profile' }, 400);
    }
    return respond(req, { link: generated.properties.action_link });
  } catch {
    return respond(req, { error: 'Invalid request' }, 400);
  }
});
