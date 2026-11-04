CREATE OR REPLACE FUNCTION public.update_own_profile (
  p_name       text,
  p_phone      text,
  p_birth_date date,
  p_address    text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 200 or
    length(coalesce(p_phone, '')) > 50 or length(coalesce(p_address, '')) > 500 or
    p_birth_date > current_date then raise exception 'Invalid profile'; end if;
  update public.profiles set full_name = trim(p_name),
    phone = nullif(trim(p_phone), ''), birth_date = p_birth_date,
    address = nullif(trim(p_address), '') where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text) FROM PUBLIC, "anon", "service_role";
