CREATE OR REPLACE FUNCTION public.employee_summary (
  p_company uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  with course_stats as (
    select c.id, count(l.id) as total, count(l.id) filter(where lp.status = 'completed') as done
    from public.courses c left join public.modules m on m.course_id = c.id
    left join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
    where public.employee_can_access_course(c.id) group by c.id
  ), days as (
    select generate_series((now() at time zone 'America/Sao_Paulo')::date - 6,
      (now() at time zone 'America/Sao_Paulo')::date, interval '1 day')::date as day
  ), activity as (
    select d.day, exists(select 1 from public.lesson_progress lp where lp.user_id = auth.uid() and lp.company_id = p_company
      and lp.updated_at >= (d.day::timestamp at time zone 'America/Sao_Paulo')
      and lp.updated_at < ((d.day + 1)::timestamp at time zone 'America/Sao_Paulo') and lp.updated_at <= now()) as active
    from days d
  ) select jsonb_build_object(
    'course_count', (select count(*) from course_stats),
    'completed_course_count', (select count(*) from course_stats where total > 0 and done = total),
    'certificate_count', (select count(*) from public.certificates where user_id = auth.uid() and company_id = p_company),
    'balance', coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = auth.uid() and lp.company_id = p_company and lp.status = 'completed'),0)
      - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id
        where d.user_id = auth.uid() and d.company_id = p_company),0),
    'department', (select dept from public.company_memberships where user_id = auth.uid() and company_id = p_company and role = 'funcionario'),
    'activity', (select jsonb_agg(to_jsonb(a) order by day) from activity a)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."employee_summary"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_summary"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_summary"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_summary"(uuid) FROM PUBLIC, "anon", "service_role";
