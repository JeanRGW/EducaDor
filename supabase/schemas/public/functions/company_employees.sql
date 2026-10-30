CREATE OR REPLACE FUNCTION public.company_employees (
  p_company uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'empresa' and
    p_company = public.own_company_id(), false) then raise exception 'Forbidden'; end if;
  with employees as (
    select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title
    from public.company_memberships cm join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company and cm.role = 'funcionario'
  ), matching as (
    select * from employees where
      strpos(lower(full_name), lower(trim(coalesce(p_search, '')))) > 0 or
      strpos(lower(coalesce(dept, '')), lower(trim(coalesce(p_search, '')))) > 0
  ), page as (
    select * from matching order by lower(full_name), user_id
    limit 50 offset greatest(coalesce(p_offset, 0), 0)
  ), items as (
    select e.*,
      (select round(100.0 * count(*) filter (where lp.status = 'completed') / nullif(count(*), 0), 1)
        from public.courses c join public.modules m on m.course_id = c.id
        join public.lessons l on l.module_id = m.id
        left join public.lesson_progress lp on lp.lesson_id = l.id
          and lp.user_id = e.user_id and lp.company_id = p_company
        where public.course_company_allowed(c.id, p_company)) as pct,
      (select max(lp.updated_at) from public.lesson_progress lp
        where lp.user_id = e.user_id and lp.company_id = p_company
          and lp.updated_at <= now()) as last_activity_at
    from page e
  )
  select jsonb_build_object(
    'total_count', (select count(*) from employees),
    'filtered_count', (select count(*) from matching),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by lower(full_name), user_id)
      from items i), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."company_employees"(uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."company_employees"(uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_employees"(uuid, text, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."company_employees"(uuid, text, integer) FROM PUBLIC, "anon", "service_role";
