CREATE OR REPLACE FUNCTION public.update_company (
  p_company uuid,
  p_fields  jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or
    length(trim(coalesce(p_fields->>'name', ''))) not between 1 and 200 or
    exists (select 1 from jsonb_each_text(p_fields) f where length(f.value) > 500) or
    (coalesce(p_fields->>'email', '') <> '' and
      p_fields->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'Invalid company';
  end if;
  -- Validate edits only: preserve historical prefixes and already issued codes.
  -- New prefixes are 1-12 ASCII uppercase letters/digits (PREFIX-XXXXXX).
  if p_fields ? 'code_prefix' and (
    jsonb_typeof(p_fields->'code_prefix') <> 'string' or
    coalesce(p_fields->>'code_prefix', '') !~ '^[A-Z0-9]{1,12}$'
  ) then
    raise exception 'Invalid certificate prefix';
  end if;
  update public.companies set name = trim(p_fields->>'name'),
    code_prefix = case when p_fields ? 'code_prefix' then p_fields->>'code_prefix' else code_prefix end,
    cnpj = nullif(trim(p_fields->>'cnpj'), ''),
    responsible = nullif(trim(p_fields->>'responsible'), ''),
    email = nullif(trim(p_fields->>'email'), ''),
    phone = nullif(trim(p_fields->>'phone'), ''),
    address = nullif(trim(p_fields->>'address'), ''),
    city = nullif(trim(p_fields->>'city'), ''),
    state = nullif(upper(trim(p_fields->>'state')), ''),
    field = nullif(trim(p_fields->>'field'), '')
    where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."update_company"(uuid, jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_company"(uuid, jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_company"(uuid, jsonb) TO "postgres";

REVOKE ALL ON FUNCTION "public"."update_company"(uuid, jsonb) FROM PUBLIC, "anon", "service_role";
