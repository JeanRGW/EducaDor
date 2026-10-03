-- Company metadata only; every RPC validates the signed session's active context.
create function public.company_dashboard(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'empresa' and
    p_company = public.own_company_id(), false) then raise exception 'Forbidden'; end if;
  with employees as (
    select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title
    from public.company_memberships cm join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company and cm.role = 'funcionario'
  ), months as (
    select generate_series(date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '5 months',
      date_trunc('month', now() at time zone 'America/Sao_Paulo'), interval '1 month')::date as month
  ), engagement as (
    select month, count(distinct lp.user_id) as active_users
    from months left join public.lesson_progress lp on lp.company_id = p_company
      and lp.updated_at >= (month::timestamp at time zone 'America/Sao_Paulo')
      and lp.updated_at < ((month + interval '1 month') at time zone 'America/Sao_Paulo')
      and lp.updated_at <= now() and exists(select 1 from employees e where e.user_id = lp.user_id)
    group by month
  ), completions as (
    select e.user_id, e.full_name, e.email, e.dept, e.job_title,
      round(100.0 * count(l.id) filter (where lp.status = 'completed') / nullif(count(l.id), 0), 1) as pct
    from employees e
    left join public.courses c on public.course_company_allowed(c.id, p_company)
    left join public.modules m on m.course_id = c.id
    left join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.user_id = e.user_id
      and lp.company_id = p_company and lp.lesson_id = l.id
    group by e.user_id, e.full_name, e.email, e.dept, e.job_title
  ), highlights as (
    select * from completions where pct > 0
    order by pct desc, lower(full_name), user_id limit 2
  )
  select jsonb_build_object(
    'employee_count', (select count(*) from employees),
    'active_course_count', (select count(*) from public.courses c
      where c.status = 'released' and public.course_company_allowed(c.id, p_company)
        and coalesce((select a.company_enabled from public.assignments a
          where a.course_id = c.id and a.company_id = p_company), true)),
    'certificate_count', (select count(*) from public.certificates where company_id = p_company),
    'completion_pct', (select pct from public.completion_by_company where company_id = p_company),
    'engagement', (select jsonb_agg(to_jsonb(e) order by month) from engagement e),
    'highlights', coalesce((select jsonb_agg(to_jsonb(h) order by pct desc, lower(full_name), user_id)
      from highlights h), '[]'::jsonb)
  ) into result;
  return result;
end $$;

create function public.company_employees(p_company uuid, p_search text default '', p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
end $$;

revoke all on function public.company_dashboard(uuid), public.company_employees(uuid, text, integer) from public, anon;
grant execute on function public.company_dashboard(uuid), public.company_employees(uuid, text, integer) to authenticated;
