CREATE OR REPLACE FUNCTION public.clear_context()
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  delete from public.session_contexts
  where user_id = (select auth.uid())
    and session_id = nullif(auth.jwt()->>'session_id', '')::uuid
$function$;

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM PUBLIC, "anon", "service_role";
