CREATE OR REPLACE FUNCTION public.available_contexts()
  RETURNS TABLE (
    role         text,
    company_id   uuid,
    company_name text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return query select 'gestor'::text, null::uuid, 'Plataforma'::text
  from public.platform_gestors pg where pg.user_id = (select auth.uid())
  union all
  select cm.role, cm.company_id, c.name from public.company_memberships cm
    join public.companies c on c.id = cm.company_id and c.active
  where cm.user_id = (select auth.uid())
  order by 1, 3;
end
$function$;

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM PUBLIC, "anon", "service_role";
