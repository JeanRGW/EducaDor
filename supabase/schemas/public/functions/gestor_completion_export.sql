CREATE OR REPLACE FUNCTION public.gestor_completion_export (
  p_after uuid DEFAULT NULL
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
  with page as (
    select c.id, c.name from public.companies c
    where p_after is null or c.id > p_after
    order by c.id
    limit 50
  ), items as (
    select p.id as company_id, p.name as company,
      (select round(100.0 * count(*) filter (where lp.status = 'completed') /
        nullif(count(*), 0), 1)
        from public.company_memberships cm
        join public.courses c on public.course_company_allowed(c.id, p.id)
        join public.modules m on m.course_id = c.id
        join public.lessons l on l.module_id = m.id
        left join public.lesson_progress lp on lp.lesson_id = l.id
          and lp.user_id = cm.user_id and lp.company_id = p.id
        where cm.company_id = p.id and cm.role = 'funcionario') as pct
    from page p
  )
  select jsonb_build_object(
    'total_count', (select count(*) from public.companies),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by company_id)
      from items i), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_completion_export"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_completion_export"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_completion_export"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_completion_export"(uuid) FROM PUBLIC, "anon", "service_role";
