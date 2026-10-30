CREATE OR REPLACE FUNCTION public.gestor_companies (
  p_search text    DEFAULT ''::text,
  p_active boolean DEFAULT NULL::boolean,
  p_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  with matching as (
    select c.* from public.companies c
    where strpos(lower(c.name), lower(trim(coalesce(p_search, '')))) > 0
  ), page as (
    select c.*, (select count(*) from public.company_memberships cm
      where cm.company_id = c.id and cm.role = 'funcionario') as employee_count
    from matching c where p_active is null or c.active = p_active
    order by lower(c.name), c.id limit 50 offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(p) order by lower(name), id) from page p), '[]'::jsonb),
    'active_count', (select count(*) from matching where active),
    'inactive_count', (select count(*) from matching where not active)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_companies"(text, boolean, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_companies"(text, boolean, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_companies"(text, boolean, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_companies"(text, boolean, integer) FROM PUBLIC, "anon", "service_role";
