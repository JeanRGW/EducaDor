-- Gestor aggregates expose metadata only and validate the active Auth session.
create index lesson_progress_updated_at_idx on public.lesson_progress(updated_at);
create index company_memberships_company_role_idx on public.company_memberships(company_id, role);

create function public.gestor_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
end $$;

create function public.gestor_companies(p_search text default '',
  p_active boolean default null, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  with matching as (
    select c.* from public.companies c
    where strpos(lower(c.name), lower(trim(coalesce(p_search, '')))) > 0
  ), page as (
    select c.*, (select count(*) from public.company_memberships cm
      where cm.company_id = c.id and cm.role = 'funcionario') as employee_count
    from matching c where p_active is null or c.active = p_active
    order by lower(c.name), c.id limit 50 offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(p) order by lower(name), id) from page p), '[]'::jsonb),
    'active_count', (select count(*) from matching where active),
    'inactive_count', (select count(*) from matching where not active)
  ) into result;
  return result;
end $$;

create function public.gestor_completion(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
end $$;

create function public.gestor_activity_report(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
end $$;

-- Filter before pagination; company names must not depend on the visible company page.
create function public.pending_invites_page(p_role text default null, p_company uuid default null)
returns table(email text, role text, company_id uuid, expires_at timestamptz,
  full_name text, company_name text)
language sql stable security definer set search_path = '' as $$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name, c.name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  left join public.companies c on c.id = mi.company_id
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
    and (p_role is null or mi.role = p_role)
    and (p_company is null or mi.company_id = p_company)
  order by mi.created_at desc, mi.id limit 50
$$;

revoke all on function public.gestor_dashboard(), public.gestor_companies(text, boolean, integer),
  public.gestor_completion(integer), public.gestor_activity_report(date, date),
  public.pending_invites_page(text, uuid) from public, anon;
grant execute on function public.gestor_dashboard(), public.gestor_companies(text, boolean, integer),
  public.gestor_completion(integer), public.gestor_activity_report(date, date),
  public.pending_invites_page(text, uuid) to authenticated;
