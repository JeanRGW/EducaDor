-- Fail closed, including missing/revoked selected contexts.
create or replace function public.ranking(p_company uuid, p_limit int default 20)
returns table(full_name text, dept text, points bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor() or (public.context_role() in ('empresa', 'funcionario')
    and p_company = public.own_company_id()), false) then raise exception 'Forbidden'; end if;
  return query select p.full_name, cm.dept,
    (coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = p.id and lp.company_id = p_company and lp.status = 'completed'), 0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id
      where d.user_id = p.id and d.company_id = p_company), 0))::bigint
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  order by 3 desc, lower(p.full_name), p.id limit least(greatest(coalesce(p_limit,20),1),100);
end $$;

-- No triggers/event logs. Ordinary direct writes obey the same monotonic invariant.
create function public.employee_progress_valid(p_lesson uuid, p_status text)
returns boolean language sql volatile security definer set search_path = '' as $$
  select coalesce(public.context_role() = 'funcionario', false)
    and p_status in ('in_progress', 'completed') and not exists (
      select 1 from public.lesson_progress lp where lp.user_id = auth.uid()
        and lp.company_id = public.own_company_id() and lp.lesson_id = p_lesson
        and lp.status = 'completed' and p_status <> 'completed')
$$;
revoke all on function public.employee_progress_valid(uuid,text) from public, anon;
grant execute on function public.employee_progress_valid(uuid,text) to authenticated;
alter table public.lesson_progress add constraint progress_nonnegative_position check(position_sec >= 0) not valid;
create policy progress_valid_insert on public.lesson_progress as restrictive for insert to authenticated
  with check(public.employee_progress_valid(lesson_id, status));
create policy progress_valid_update on public.lesson_progress as restrictive for update to authenticated
  with check(public.employee_progress_valid(lesson_id, status));

create function public.employee_catalog(p_company uuid, p_search text default '', p_kind text default null,
  p_state text default null, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset < 0 or p_offset is null or (p_kind is not null and p_kind not in ('video','audio','pdf','quiz','reading'))
    or (p_state is not null and p_state not in ('not_started','in_progress','completed')) then raise exception 'Invalid query'; end if;
  with catalog as (
    select c.id, c.title, c.description, c.cover_key,
      count(l.id)::int as lesson_count, count(l.id) filter(where lp.status = 'completed')::int as completed_count,
      max(lp.updated_at) as last_activity_at,
      case when count(l.id) > 0 and count(l.id) = count(l.id) filter(where lp.status = 'completed') then 'completed'
        when count(lp.lesson_id) > 0 then 'in_progress' else 'not_started' end as state
    from public.courses c left join public.modules m on m.course_id = c.id
    left join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
    where public.employee_can_access_course(c.id)
      and strpos(lower(c.title), lower(trim(coalesce(p_search,'')))) > 0
      and (p_kind is null or exists(select 1 from public.modules fm join public.lessons fl on fl.module_id = fm.id
        where fm.course_id = c.id and fl.kind = p_kind))
    group by c.id
  ), matching as (select * from catalog where p_state is null or state = p_state), page as (
    select * from matching order by last_activity_at desc nulls last, lower(title), id limit 50 offset p_offset
  ) select jsonb_build_object('total', (select count(*) from matching), 'items',
    coalesce((select jsonb_agg(to_jsonb(p) order by last_activity_at desc nulls last, lower(title), id) from page p),'[]'::jsonb)) into result;
  return result;
end $$;

create function public.employee_summary(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
end $$;

create function public.employee_lessons(p_company uuid, p_course uuid, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if not public.employee_can_access_course(p_course) then raise exception 'Course unavailable'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total', (select count(*) from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course),
    'items', coalesce((select jsonb_agg(to_jsonb(page) order by module_position, module_id, position, id) from (
      select l.id, l.title, l.kind, l.video_id, m.id as module_id, m.title as module_title,
        m.position as module_position, l.position, coalesce(lp.status,'not_started') as status,
        greatest(coalesce(lp.position_sec,0),0) as position_sec
      from public.modules m join public.lessons l on l.module_id = m.id
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
      where m.course_id = p_course order by m.position, m.id, l.position, l.id limit 50 offset p_offset
    ) page),'[]'::jsonb)) into result;
  return result;
end $$;

create function public.save_employee_progress(p_company uuid, p_lesson uuid, p_position int, p_completed boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  if p_position is null or p_position < 0 or p_completed is null then raise exception 'Invalid progress'; end if;
  perform 1 from public.lessons l join public.modules m on m.id = l.module_id join public.courses c on c.id=m.course_id
    where l.id = p_lesson and l.kind = 'video' and l.video_id is not null and public.employee_can_access_course(m.course_id) for share of c;
  if not found then raise exception 'Lesson unavailable'; end if;
  insert into public.lesson_progress(user_id,company_id,lesson_id,status,position_sec)
    values(auth.uid(),p_company,p_lesson,case when p_completed then 'completed' else 'in_progress' end,p_position)
    on conflict(user_id,company_id,lesson_id) do update set
      status = case when lesson_progress.status = 'completed' or p_completed then 'completed' else 'in_progress' end,
      position_sec = excluded.position_sec, updated_at = now();
end $$;

create function public.redeem_employee_reward(p_company uuid,p_reward uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform public.redeem_reward(p_reward);
end $$;
revoke all on function public.redeem_employee_reward(uuid,uuid) from public,anon;
grant execute on function public.redeem_employee_reward(uuid,uuid) to authenticated;

create function public.employee_certificates(p_company uuid, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total',(select count(*) from public.certificates where user_id = auth.uid() and company_id = p_company),
    'items',coalesce((select jsonb_agg(to_jsonb(p) order by issued_at desc,id) from (
      select ce.id, ce.code, ce.issued_at, ce.course_id, c.title as course_title,
        co.name as company_name, pr.full_name as employee_name
      from public.certificates ce join public.courses c on c.id = ce.course_id
      join public.companies co on co.id = ce.company_id join public.profiles pr on pr.id = ce.user_id
      where ce.user_id = auth.uid() and ce.company_id = p_company order by ce.issued_at desc,ce.id limit 50 offset p_offset
    ) p),'[]'::jsonb)) into result;
  return result;
end $$;

create function public.employee_ranking(p_company uuid)
returns table(user_id uuid, full_name text, dept text, points bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  return query select cm.user_id,p.full_name,cm.dept,
    coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id where lp.user_id = cm.user_id and lp.company_id = p_company and lp.status = 'completed'),0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id where d.user_id = cm.user_id and d.company_id = p_company),0)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario' order by 4 desc,lower(p.full_name),cm.user_id limit 3;
end $$;

-- Only the verified Edge Function can invoke this. Revalidate the selected session in DB.
create function public.issue_employee_certificate(p_user uuid, p_session uuid, p_company uuid, p_course uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid; prefix text; code_value text;
begin
  perform pg_advisory_xact_lock(hashtext(p_user::text || p_company::text || p_course::text));
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id = sc.user_id and cm.company_id = sc.company_id and cm.role = sc.role
    join public.companies co on co.id = cm.company_id and co.active
    where sc.user_id = p_user and sc.session_id = p_session and sc.role = 'funcionario' and sc.company_id = p_company for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform 1 from public.courses c where c.id = p_course and c.status = 'released' and public.course_company_allowed(c.id,p_company)
    and coalesce((select company_enabled from public.assignments a where a.course_id = c.id and a.company_id = p_company),true) for share;
  if not found then raise exception 'Course unavailable'; end if;
  if not exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course)
    or exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = p_user and lp.company_id = p_company
      where m.course_id = p_course and lp.status is distinct from 'completed') then raise exception 'Course incomplete'; end if;
  select id into result from public.certificates where user_id = p_user and company_id = p_company and course_id = p_course;
  if found then return result; end if;
  select co.code_prefix into prefix from public.companies co where co.id = p_company;
  for attempt in 1..10 loop
    code_value := prefix || '-';
    for digit in 1..6 loop code_value := code_value || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ',1+floor(random()*32)::int,1); end loop;
    begin
      insert into public.certificates(user_id,company_id,course_id,code) values(p_user,p_company,p_course,code_value) returning id into result;
      return result;
    exception when unique_violation then null;
    end;
  end loop;
  raise exception 'Certificate code unavailable';
end $$;
revoke all on function public.issue_employee_certificate(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.issue_employee_certificate(uuid,uuid,uuid,uuid) to service_role;

revoke all on function public.employee_catalog(uuid,text,text,text,int), public.employee_summary(uuid), public.employee_lessons(uuid,uuid,int),
  public.save_employee_progress(uuid,uuid,int,boolean), public.employee_certificates(uuid,int),public.employee_ranking(uuid) from public,anon;
grant execute on function public.employee_catalog(uuid,text,text,text,int), public.employee_summary(uuid), public.employee_lessons(uuid,uuid,int),
  public.save_employee_progress(uuid,uuid,int,boolean), public.employee_certificates(uuid,int),public.employee_ranking(uuid) to authenticated;
