-- Existing catalogs retain their explicit assignments; new trails include future companies.
alter table public.courses add column all_companies boolean not null default false;
alter table public.courses alter column all_companies set default true;
alter table public.assignments add column company_enabled boolean not null default true;

-- Keep platform eligibility separate from the company's own pause preference.
create function public.course_company_allowed(p_course uuid, p_company uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.courses c where c.id = p_course and
      (c.all_companies or exists (
        select 1 from public.assignments a where a.course_id = c.id
          and a.company_id = p_company and a.released)))
$$;
revoke all on function public.course_company_allowed(uuid, uuid) from public, anon, authenticated;

create function public.employee_can_access_course(p_course uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.context_role() = 'funcionario', false)
    and exists (
      select 1 from public.courses c
      where c.id = p_course and c.status = 'released'
        and public.course_company_allowed(c.id, public.own_company_id())
        and coalesce((select a.company_enabled from public.assignments a
          where a.course_id = c.id and a.company_id = public.own_company_id()), true))
$$;
revoke all on function public.employee_can_access_course(uuid) from public, anon;
grant execute on function public.employee_can_access_course(uuid) to authenticated;

drop policy courses_select on public.courses;
create policy courses_select on public.courses for select to authenticated
  using (public.is_gestor() or public.employee_can_access_course(id));
drop policy modules_select on public.modules;
create policy modules_select on public.modules for select to authenticated
  using (public.is_gestor() or public.employee_can_access_course(course_id));
drop policy lessons_select on public.lessons;
create policy lessons_select on public.lessons for select to authenticated
  using (public.is_gestor() or exists (
    select 1 from public.modules m where m.id = lessons.module_id
      and public.employee_can_access_course(m.course_id)));

drop policy progress_insert on public.lesson_progress;
drop policy progress_update on public.lesson_progress;
create policy progress_insert on public.lesson_progress for insert to authenticated
  with check (public.context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = public.own_company_id() and exists (
      select 1 from public.lessons l join public.modules m on m.id = l.module_id
      where l.id = lesson_progress.lesson_id and public.employee_can_access_course(m.course_id)));
create policy progress_update on public.lesson_progress for update to authenticated
  using (public.context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = public.own_company_id() and exists (
      select 1 from public.lessons l join public.modules m on m.id = l.module_id
      where l.id = lesson_progress.lesson_id and public.employee_can_access_course(m.course_id)))
  with check (public.context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = public.own_company_id() and exists (
      select 1 from public.lessons l join public.modules m on m.id = l.module_id
      where l.id = lesson_progress.lesson_id and public.employee_can_access_course(m.course_id)));

create function public.set_course_platform_enabled(p_course uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_enabled is null then raise exception 'Invalid state'; end if;
  update public.courses set status = case when p_enabled then 'released' else 'paused' end
    where id = p_course;
  if not found then raise exception 'Course unavailable'; end if;
end $$;

create function public.set_course_audience(p_course uuid, p_all_companies boolean,
  p_company_ids uuid[] default '{}')
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_all_companies is null or p_company_ids is null or
    (not p_all_companies and cardinality(p_company_ids) = 0) or
    exists (select 1 from unnest(p_company_ids) as ids(company_id)
      where ids.company_id is null or not exists (
        select 1 from public.companies c where c.id = ids.company_id)) then
    raise exception 'Invalid audience';
  end if;
  -- Serialize audience replacement with company changes on the same trail.
  perform 1 from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  update public.courses set all_companies = p_all_companies where id = p_course;
  if not p_all_companies then
    update public.assignments set released = false where course_id = p_course;
    insert into public.assignments(course_id, company_id, released)
      select p_course, id, true from (select distinct unnest(p_company_ids) as id) ids
      on conflict (course_id, company_id) do update set released = true;
  end if;
end $$;

create function public.set_course_company_enabled(p_course uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare cid uuid := public.own_company_id();
begin
  if public.context_role() is distinct from 'empresa' or cid is null then
    raise exception 'Forbidden';
  end if;
  if p_enabled is null then raise exception 'Invalid state'; end if;
  perform 1 from public.courses where id = p_course for update;
  if not found or not public.course_company_allowed(p_course, cid) then
    raise exception 'Course unavailable';
  end if;
  insert into public.assignments(course_id, company_id, released, company_enabled)
    values (p_course, cid, false, p_enabled)
    on conflict (course_id, company_id) do update set company_enabled = excluded.company_enabled;
end $$;

revoke all on function public.set_course_platform_enabled(uuid, boolean),
  public.set_course_audience(uuid, boolean, uuid[]),
  public.set_course_company_enabled(uuid, boolean) from public, anon;
grant execute on function public.set_course_platform_enabled(uuid, boolean),
  public.set_course_audience(uuid, boolean, uuid[]),
  public.set_course_company_enabled(uuid, boolean) to authenticated;

-- Metadata and aggregates only: company managers never receive lessons or file keys.
create function public.content_catalog(p_search text default '', p_kind text default null,
  p_offset int default 0, p_limit int default 50)
returns table(id uuid, title text, kind text, description text, cover_key text,
  platform_enabled boolean, all_companies boolean, company_enabled boolean,
  company_ids uuid[], company_count bigint, lesson_count bigint, completion_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid := public.own_company_id(); platform boolean := coalesce(public.is_gestor(), false);
begin
  if not platform and (public.context_role() is distinct from 'empresa' or cid is null) then
    raise exception 'Forbidden';
  end if;
  return query
  with page as (
    select c.* from public.courses c
    where (platform or public.course_company_allowed(c.id, cid))
      and (p_kind is null or c.kind = p_kind)
      and (coalesce(p_search, '') = '' or strpos(lower(c.title), lower(p_search)) > 0)
    order by c.created_at desc, c.id
    limit least(greatest(coalesce(p_limit, 50), 1), 50)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select c.id, c.title, c.kind, c.description, c.cover_key, c.status = 'released',
    c.all_companies,
    case when platform then true else coalesce((select a.company_enabled
      from public.assignments a where a.course_id = c.id and a.company_id = cid), true) end,
    case when platform then array(select a.company_id from public.assignments a
      where a.course_id = c.id and a.released order by a.company_id) else null::uuid[] end,
    case when platform then (select count(*) from public.companies co where co.active
      and public.course_company_allowed(c.id, co.id)) else 1::bigint end,
    (select count(*) from public.lessons l join public.modules m on m.id = l.module_id
      where m.course_id = c.id),
    (select round(100.0 * count(*) filter (where lp.status = 'completed')
      / nullif(count(*), 0), 1)
      from public.modules m join public.lessons l on l.module_id = m.id
      join public.company_memberships cm on cm.role = 'funcionario'
      join public.companies co on co.id = cm.company_id and co.active
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
        and lp.company_id = cm.company_id
      where m.course_id = c.id and public.course_company_allowed(c.id, cm.company_id)
        and (platform or cm.company_id = cid))
  from page c order by c.created_at desc, c.id;
end $$;
revoke all on function public.content_catalog(text, text, int, int) from public, anon;
grant execute on function public.content_catalog(text, text, int, int) to authenticated;

-- Publishing is atomic; video stays on YouTube, never in Storage.
create function public.publish_video_trail(p_title text, p_description text,
  p_module_title text, p_video_id text, p_all_companies boolean default true,
  p_company_ids uuid[] default '{}')
returns uuid language plpgsql security definer set search_path = '' as $$
declare course_id uuid; module_id uuid;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 or p_module_title is null or
    length(trim(p_module_title)) not between 1 and 200 or
    p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    raise exception 'Invalid trail';
  end if;
  insert into public.courses(title, kind, description, status, created_by, all_companies)
    values (trim(p_title), 'course', coalesce(p_description, ''), 'released', auth.uid(), true)
    returning id into course_id;
  perform public.set_course_audience(course_id, p_all_companies, p_company_ids);
  insert into public.modules(course_id, title, position)
    values (course_id, trim(p_module_title), 1) returning id into module_id;
  insert into public.lessons(module_id, title, kind, video_provider, video_id, position)
    values (module_id, trim(p_title), 'video', 'youtube', p_video_id, 1);
  return course_id;
end $$;
revoke all on function public.publish_video_trail(text, text, text, text, boolean, uuid[])
  from public, anon;
grant execute on function public.publish_video_trail(text, text, text, text, boolean, uuid[])
  to authenticated;

-- Reports retain progress through pauses; audience eligibility controls their denominator.
create or replace view public.completion_by_company as
select co.id as company_id, co.name as company,
  round(100.0 * count(*) filter (where lp.status = 'completed') / nullif(count(*), 0), 1) as pct
from public.companies co
join public.company_memberships cm on cm.company_id = co.id and cm.role = 'funcionario'
join public.courses c on c.all_companies or exists (
  select 1 from public.assignments a where a.course_id = c.id and a.company_id = co.id and a.released)
join public.modules m on m.course_id = c.id
join public.lessons l on l.module_id = m.id
left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
  and lp.company_id = co.id
where public.is_gestor() or (public.context_role() = 'empresa' and co.id = public.own_company_id())
group by co.id;

create or replace view public.completion_by_dept as
select cm.company_id, cm.dept as department,
  round(100.0 * count(*) filter (where lp.status = 'completed') / nullif(count(*), 0), 1) as pct
from public.company_memberships cm
join public.courses c on c.all_companies or exists (
  select 1 from public.assignments a where a.course_id = c.id
    and a.company_id = cm.company_id and a.released)
join public.modules m on m.course_id = c.id
join public.lessons l on l.module_id = m.id
left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
  and lp.company_id = cm.company_id
where cm.role = 'funcionario' and (public.is_gestor() or
  (public.context_role() = 'empresa' and cm.company_id = public.own_company_id()))
group by cm.company_id, cm.dept;

create or replace function public.employee_completion(p_company uuid)
returns table(user_id uuid, full_name text, email text, dept text, job_title text, pct numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id()), false) then
    raise exception 'Forbidden';
  end if;
  return query
  select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title,
    round(100.0 * count(l.id) filter (where lp.status = 'completed') / nullif(count(l.id), 0), 1)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  left join public.courses c on public.course_company_allowed(c.id, cm.company_id)
  left join public.modules m on m.course_id = c.id
  left join public.lessons l on l.module_id = m.id
  left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
    and lp.company_id = cm.company_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  group by cm.user_id, p.id, cm.dept, cm.job_title
  order by p.full_name limit 50;
end $$;
