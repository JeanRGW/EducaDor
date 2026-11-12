SET local check_function_bodies = off;

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

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

REVOKE ALL ("avatar_key") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("avatar_key") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("email") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("email") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("full_name") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("id") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("needs_password") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("needs_password") ON TABLE "public"."profiles" TO "authenticated";
