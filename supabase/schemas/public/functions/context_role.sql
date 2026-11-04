CREATE OR REPLACE FUNCTION public.context_role()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return (select sc.role from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and (
      (sc.role = 'gestor' and exists (
        select 1 from public.platform_gestors pg where pg.user_id = sc.user_id))
      or (sc.role in ('empresa', 'funcionario') and exists (
        select 1 from public.company_memberships cm
        join public.companies c on c.id = cm.company_id and c.active
        where cm.user_id = sc.user_id and cm.company_id = sc.company_id
          and cm.role = sc.role))
    )
  limit 1);
end
$function$;

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."context_role"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."context_role"() FROM PUBLIC, "anon", "service_role";
