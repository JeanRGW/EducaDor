CREATE OR REPLACE FUNCTION public.platform_professionals_page (p_search text DEFAULT '', p_offset integer DEFAULT 0)
RETURNS TABLE (id uuid, full_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select p.id, p.full_name from public.profiles p
  join public.platform_gestors g on g.user_id = p.id
  where strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0
  order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

GRANT EXECUTE ON FUNCTION public.platform_professionals_page(text, integer) TO authenticated, postgres;
REVOKE ALL ON FUNCTION public.platform_professionals_page(text, integer) FROM PUBLIC, anon, service_role;
