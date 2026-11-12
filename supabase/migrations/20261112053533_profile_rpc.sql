SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.own_profile()
  RETURNS TABLE (
    id             uuid,
    full_name      text,
    email          text,
    needs_password boolean,
    phone          text,
    birth_date     date,
    address        text,
    gender         text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
BEGIN
  PERFORM public.require_mfa_if_enrolled();
  RETURN QUERY SELECT p.id, p.full_name, p.email, p.needs_password, p.phone, p.birth_date, p.address, p.gender
    FROM public.profiles p WHERE p.id = auth.uid();
END;
$function$;

REVOKE ALL ON FUNCTION "public"."own_profile"() FROM PUBLIC, "anon", "service_role";

GRANT EXECUTE ON FUNCTION "public"."own_profile"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."own_profile"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."own_profile"() TO "postgres";
