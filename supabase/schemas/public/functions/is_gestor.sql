CREATE OR REPLACE FUNCTION public.is_gestor()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $function$
  select public.context_role() = 'gestor'
$function$;

GRANT EXECUTE ON FUNCTION "public"."is_gestor"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."is_gestor"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."is_gestor"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."is_gestor"() FROM PUBLIC, "anon", "service_role";
