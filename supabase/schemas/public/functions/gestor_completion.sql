CREATE OR REPLACE FUNCTION public.gestor_completion (
  p_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select coalesce(jsonb_agg(to_jsonb(page) order by pct desc nulls last, company, company_id), '[]'::jsonb)
  into result from (
    select c.id as company_id, c.name as company, r.pct
    from public.companies c left join public.completion_by_company r on r.company_id = c.id
    order by r.pct desc nulls last, c.name, c.id
    limit 50 offset greatest(coalesce(p_offset, 0), 0)
  ) page;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_completion"(integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_completion"(integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_completion"(integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_completion"(integer) FROM PUBLIC, "anon", "service_role";
