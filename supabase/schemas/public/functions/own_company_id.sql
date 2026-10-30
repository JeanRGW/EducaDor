CREATE OR REPLACE FUNCTION public.own_company_id()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$function$;

GRANT EXECUTE ON FUNCTION "public"."own_company_id"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."own_company_id"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."own_company_id"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."own_company_id"() FROM PUBLIC, "anon", "service_role";
