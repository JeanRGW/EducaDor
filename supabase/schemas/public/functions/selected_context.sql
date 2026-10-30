CREATE OR REPLACE FUNCTION public.selected_context()
  RETURNS TABLE (
    role       text,
    company_id uuid
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select sc.role, sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$function$;

GRANT EXECUTE ON FUNCTION "public"."selected_context"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."selected_context"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."selected_context"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."selected_context"() FROM PUBLIC, "anon", "service_role";
