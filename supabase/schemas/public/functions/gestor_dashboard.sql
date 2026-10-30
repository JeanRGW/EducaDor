CREATE OR REPLACE FUNCTION public.gestor_dashboard()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  with clock as (
    select (now() at time zone 'America/Sao_Paulo')::date as today
  ), months as (
    select generate_series(date_trunc('month', today) - interval '5 months',
      date_trunc('month', today), interval '1 month')::date as month from clock
  ), opportunities as (
    select lp.status
    from public.company_memberships cm
    join public.courses c on public.course_company_allowed(c.id, cm.company_id)
    join public.modules m on m.course_id = c.id
    join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.user_id = cm.user_id
      and lp.company_id = cm.company_id and lp.lesson_id = l.id
    where cm.role = 'funcionario'
  ), growth as (
    select month,
      (select count(*) from public.companies c where c.created_at <
        ((month + interval '1 month') at time zone 'America/Sao_Paulo')) as companies,
      (select count(*) from public.profiles p join auth.users u on u.id = p.id
        where u.created_at < ((month + interval '1 month') at time zone 'America/Sao_Paulo')) as users
    from months
  ), recent_companies as (
    select c.* from public.companies c order by c.created_at desc, c.id limit 10
  ), recent_progress as (
    select lp.* from public.lesson_progress lp
    order by lp.updated_at desc, lp.company_id, lp.user_id, lp.lesson_id limit 10
  ), recent as (
    select 'company:' || c.id::text as id, 'company'::text as kind,
      c.name as name, null::text as title, c.created_at as occurred_at
    from recent_companies c
    union all
    select 'progress:' || lp.company_id::text || ':' || lp.user_id::text || ':' || lp.lesson_id::text,
      'progress', p.full_name, l.title, lp.updated_at
    from recent_progress lp join public.profiles p on p.id = lp.user_id
    join public.lessons l on l.id = lp.lesson_id
  ), latest as (
    select * from recent order by occurred_at desc, id limit 10
  )
  select jsonb_build_object(
    'company_count', (select count(*) from public.companies),
    'new_company_count', (select count(*) from public.companies c, clock
      where c.created_at >= (date_trunc('month', today)::timestamp at time zone 'America/Sao_Paulo')),
    'user_count', (select count(*) from public.profiles),
    'active_user_count', (select count(distinct user_id) from public.lesson_progress
      where updated_at >= now() - interval '30 days' and updated_at <= now()),
    'completion_pct', (select round(100.0 * count(*) filter (where status = 'completed')
      / nullif(count(*), 0), 1) from opportunities),
    'growth', (select jsonb_agg(to_jsonb(g) order by month) from growth g),
    'activities', coalesce((select jsonb_agg(to_jsonb(a) order by occurred_at desc, id)
      from latest a), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."gestor_dashboard"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_dashboard"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_dashboard"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_dashboard"() FROM PUBLIC, "anon", "service_role";
