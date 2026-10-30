CREATE OR REPLACE FUNCTION public.gestor_managers (
  p_company uuid    DEFAULT NULL::uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS TABLE (
    id        uuid,
    full_name text,
    email     text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then
    raise exception 'Invalid page';
  end if;
  return query select p.id, p.full_name, p.email from public.profiles p
    where (case when p_company is null then exists (
      select 1 from public.platform_gestors g where g.user_id = p.id)
    else exists (select 1 from public.company_memberships m
      where m.user_id = p.id and m.company_id = p_company and m.role = 'empresa') end)
    and (strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0 or
      strpos(lower(p.email), lower(coalesce(p_search, ''))) > 0)
    order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_managers"(uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_managers"(uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_managers"(uuid, text, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_managers"(uuid, text, integer) FROM PUBLIC, "anon", "service_role";
