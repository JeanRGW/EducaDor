CREATE OR REPLACE FUNCTION public.company_managers_page (p_company uuid, p_search text DEFAULT '', p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, full_name text, email text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if not coalesce(public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id()), false) then
    raise exception 'Forbidden';
  end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select p.id, p.full_name, p.email from public.profiles p
  join public.company_memberships m on m.user_id = p.id
  where m.company_id = p_company and m.role = 'empresa'
    and (strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(p.email), lower(coalesce(p_search, ''))) > 0)
  order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

GRANT EXECUTE ON FUNCTION public.company_managers_page(uuid, text, integer) TO authenticated, postgres;
REVOKE ALL ON FUNCTION public.company_managers_page(uuid, text, integer) FROM PUBLIC, anon, service_role;
