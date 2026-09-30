-- Changing the return columns requires recreating the function.
drop function public.pending_invites();
create function public.pending_invites()
returns table(email text, role text, company_id uuid, expires_at timestamptz, full_name text)
language sql stable security definer set search_path = '' as $$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
  order by mi.created_at desc limit 50
$$;
revoke all on function public.pending_invites() from public, anon;
grant execute on function public.pending_invites() to authenticated;
