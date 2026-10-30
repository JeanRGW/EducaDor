CREATE OR REPLACE FUNCTION public.set_company_active (
  p_company uuid,
  p_active  boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_active is null then raise exception 'Invalid company'; end if;
  update public.companies set active = p_active where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
  -- Pauses retain grants, progress and the selected contexts for reactivation.
end $function$;

GRANT EXECUTE ON FUNCTION "public"."set_company_active"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_company_active"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_company_active"(uuid, boolean) TO "postgres";

REVOKE ALL ON FUNCTION "public"."set_company_active"(uuid, boolean) FROM PUBLIC, "anon", "service_role";
