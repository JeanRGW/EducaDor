SET local check_function_bodies = off;

DROP FUNCTION "public"."clear_context"();

CREATE OR REPLACE FUNCTION public.clear_context()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  delete from public.session_contexts
  where user_id = (select auth.uid())
    and session_id = nullif(auth.jwt()->>'session_id', '')::uuid;
end
$function$;

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM PUBLIC, "anon", "service_role";

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "postgres";
