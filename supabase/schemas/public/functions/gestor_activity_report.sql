CREATE OR REPLACE FUNCTION public.gestor_activity_report (
  p_from date,
  p_to   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb; start_at timestamptz; end_at timestamptz;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 365 then
    raise exception 'Invalid period';
  end if;
  start_at := p_from::timestamp at time zone 'America/Sao_Paulo';
  end_at := (p_to + 1)::timestamp at time zone 'America/Sao_Paulo';
  with activity as (
    select lp.* from public.lesson_progress lp
    where lp.updated_at >= start_at and lp.updated_at < end_at
  ), months as (
    select generate_series(date_trunc('month', p_from::timestamp),
      date_trunc('month', p_to::timestamp), interval '1 month')::date as month
  ), engagement as (
    select m.month, count(distinct a.user_id) as active_users
    from months m left join activity a on
      date_trunc('month', a.updated_at at time zone 'America/Sao_Paulo')::date = m.month
    group by m.month
  ), popular as (
    select c.id as course_id, c.title, c.kind, count(*) as completions
    from activity a join public.lessons l on l.id = a.lesson_id
    join public.modules m on m.id = l.module_id join public.courses c on c.id = m.course_id
    where a.status = 'completed'
    group by c.id order by completions desc, c.id limit 10
  )
  select jsonb_build_object(
    'engagement', (select jsonb_agg(to_jsonb(e) order by month) from engagement e),
    'popular_content', coalesce((select jsonb_agg(to_jsonb(p) order by completions desc, course_id)
      from popular p), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_activity_report"(date, date) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_activity_report"(date, date) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_activity_report"(date, date) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_activity_report"(date, date) FROM PUBLIC, "anon", "service_role";
