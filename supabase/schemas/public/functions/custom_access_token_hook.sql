CREATE OR REPLACE FUNCTION public.custom_access_token_hook (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_set(event, '{claims}',
    coalesce(event->'claims', '{}'::jsonb) - 'user_role' - 'company_id')
$function$;

GRANT EXECUTE ON FUNCTION "public"."custom_access_token_hook"(jsonb) TO "supabase_auth_admin";

REVOKE ALL ON FUNCTION "public"."custom_access_token_hook"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."custom_access_token_hook"(jsonb) TO "postgres";

REVOKE ALL ON FUNCTION "public"."custom_access_token_hook"(jsonb) FROM PUBLIC, "anon", "authenticated", "service_role";
