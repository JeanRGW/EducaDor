CREATE OR REPLACE FUNCTION public.directory_pending_invites (p_role text DEFAULT NULL, p_company uuid DEFAULT NULL, p_search text DEFAULT '', p_offset integer DEFAULT 0)
RETURNS TABLE (email text, role text, company_id uuid, expires_at timestamptz, full_name text, company_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if not coalesce(public.is_gestor() or public.context_role() = 'empresa', false) then
    raise exception 'Forbidden';
  end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name, c.name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  left join public.companies c on c.id = mi.company_id
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
    and (p_role is null or mi.role = p_role)
    and (p_company is null or mi.company_id = p_company)
    and (strpos(lower(mi.email), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(coalesce(p.full_name, '')), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(coalesce(c.name, '')), lower(coalesce(p_search, ''))) > 0)
  order by mi.created_at desc, mi.id limit 50 offset p_offset;
end $function$;

GRANT EXECUTE ON FUNCTION public.directory_pending_invites(text, uuid, text, integer) TO authenticated, postgres;
REVOKE ALL ON FUNCTION public.directory_pending_invites(text, uuid, text, integer) FROM PUBLIC, anon, service_role;
