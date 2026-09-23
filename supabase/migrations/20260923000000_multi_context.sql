-- One Auth identity can hold a platform grant and any number of company roles.
-- Keep this additive to the existing migrations; do not edit an applied migration.

drop view if exists completion_by_company, completion_by_dept,
  engagement_monthly, popular_content;
drop function if exists ranking(uuid, int);

create table platform_gestors (
  user_id uuid primary key references profiles(id) on delete cascade
);
create table company_memberships (
  user_id uuid not null references profiles(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  role text not null check (role in ('empresa', 'funcionario')),
  dept text,
  job_title text,
  primary key (user_id, company_id, role)
);
insert into platform_gestors(user_id)
select id from profiles where role = 'gestor';
insert into company_memberships(user_id, company_id, role, dept, job_title)
select id, company_id, role, dept, job_title from profiles
where role in ('empresa', 'funcionario') and company_id is not null;

-- Backfill the old single-company records before removing the legacy columns.
alter table lesson_progress add column company_id uuid references companies(id);
alter table certificates add column company_id uuid references companies(id);
alter table redemptions add column company_id uuid references companies(id);
update lesson_progress lp set company_id = p.company_id
from profiles p where p.id = lp.user_id;
update certificates c set company_id = p.company_id
from profiles p where p.id = c.user_id;
update redemptions r set company_id = p.company_id
from profiles p where p.id = r.user_id;
-- Fail rather than silently assigning a user's learning to the wrong company.
do $$ begin
  if exists (select 1 from lesson_progress where company_id is null)
    or exists (select 1 from certificates where company_id is null)
    or exists (select 1 from redemptions where company_id is null) then
    raise exception 'Cannot migrate learning records without a company';
  end if;
end $$;
alter table lesson_progress alter column company_id set not null;
alter table certificates alter column company_id set not null;
alter table redemptions alter column company_id set not null;
alter table lesson_progress drop constraint lesson_progress_pkey;
alter table lesson_progress add primary key (user_id, company_id, lesson_id);
alter table certificates drop constraint certificates_user_id_course_id_key;
alter table certificates add unique (user_id, company_id, course_id);

drop policy profiles_select on profiles;
drop policy profiles_insert on profiles;
drop policy profiles_update on profiles;
drop policy progress_select on lesson_progress;
drop policy certificates_select on certificates;
alter table profiles drop column role, drop column company_id,
  drop column dept, drop column job_title;
alter table profiles add column needs_password bool not null default false;
create unique index profiles_email_ci on profiles (lower(email));

-- A link is a bearer credential. Store only its hash; invitations are not a
-- history/event table and contain no reusable Auth tokens.
create table membership_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  role text not null check (role in ('gestor', 'empresa', 'funcionario')),
  company_id uuid references companies(id) on delete cascade,
  dept text,
  job_title text,
  invited_by uuid references profiles(id) on delete set null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint invite_scope check (
    (role = 'gestor' and company_id is null) or
    (role in ('empresa', 'funcionario') and company_id is not null))
);
create unique index membership_invites_unique_pending
  on membership_invites(lower(email), role,
    coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid));
alter table membership_invites enable row level security;
revoke all on membership_invites from public, anon, authenticated;

-- No client access to this table. Its row is the active context of ONE Auth
-- session (not a user-wide setting shared across devices).
create table session_contexts (
  session_id uuid primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null check (role in ('gestor', 'empresa', 'funcionario')),
  company_id uuid references companies(id) on delete cascade,
  updated_at timestamptz not null default now(),
  constraint context_scope check (
    (role = 'gestor' and company_id is null) or
    (role in ('empresa', 'funcionario') and company_id is not null))
);
create index session_contexts_user_id_idx on session_contexts(user_id);
alter table session_contexts enable row level security;
revoke all on session_contexts from public, anon, authenticated;

alter table platform_gestors enable row level security;
alter table company_memberships enable row level security;

-- Existing dashboard hook remains installed, but authorization now consults
-- current DB memberships instead of single, potentially stale JWT claims.
create or replace function custom_access_token_hook(event jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_set(event, '{claims}',
    coalesce(event->'claims', '{}'::jsonb) - 'user_role' - 'company_id')
$$;

create or replace function context_role()
returns text language sql stable security definer set search_path = '' as $$
  select sc.role from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and (
      (sc.role = 'gestor' and exists (
        select 1 from public.platform_gestors pg where pg.user_id = sc.user_id))
      or (sc.role in ('empresa', 'funcionario') and exists (
        select 1 from public.company_memberships cm
        join public.companies c on c.id = cm.company_id and c.active
        where cm.user_id = sc.user_id and cm.company_id = sc.company_id
          and cm.role = sc.role))
    )
  limit 1
$$;
create or replace function is_gestor()
returns bool language sql stable as $$
  select public.context_role() = 'gestor'
$$;
create or replace function own_company_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$$;

create function available_contexts()
returns table(role text, company_id uuid, company_name text)
language sql stable security definer set search_path = '' as $$
  select 'gestor'::text, null::uuid, 'Plataforma'::text
  from public.platform_gestors where user_id = (select auth.uid())
  union all
  select cm.role, cm.company_id, c.name from public.company_memberships cm
    join public.companies c on c.id = cm.company_id and c.active
  where cm.user_id = (select auth.uid())
  order by 1, 3
$$;
create function selected_context()
returns table(role text, company_id uuid)
language sql stable security definer set search_path = '' as $$
  select sc.role, sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$$;
create function select_context(p_role text, p_company_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if auth.uid() is null or sid is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.available_contexts() ac
    where ac.role = p_role and ac.company_id is not distinct from p_company_id) then
    raise exception 'Context unavailable';
  end if;
  insert into public.session_contexts(session_id, user_id, role, company_id)
  values (sid, auth.uid(), p_role, p_company_id)
  on conflict (session_id) do update set role = excluded.role,
    company_id = excluded.company_id, updated_at = now()
  where session_contexts.user_id = excluded.user_id;
  if not found then raise exception 'Session mismatch'; end if;
end $$;
create function clear_context()
returns void language sql security definer set search_path = '' as $$
  delete from public.session_contexts
  where user_id = (select auth.uid())
    and session_id = nullif(auth.jwt()->>'session_id', '')::uuid
$$;
revoke all on function context_role(), available_contexts(), selected_context(),
  select_context(text, uuid), clear_context() from public, anon;
grant execute on function context_role(), available_contexts(), selected_context(),
  select_context(text, uuid), clear_context() to authenticated;

-- Identity columns are server-managed, including email (Auth owns the login).
create policy profiles_select on profiles for select to authenticated using (
  id = auth.uid() or is_gestor() or
  (context_role() = 'empresa' and exists (
    select 1 from company_memberships cm where cm.user_id = profiles.id
      and cm.company_id = own_company_id())));
create policy profiles_update on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke all on profiles from authenticated;
grant select on profiles to authenticated;
grant update(full_name, avatar_key, phone, birth_date, address, needs_password)
  on profiles to authenticated;

create policy platform_gestors_select on platform_gestors for select to authenticated
  using (user_id = auth.uid() or is_gestor());
create policy company_memberships_select on company_memberships for select to authenticated
  using (user_id = auth.uid() or is_gestor() or
    (context_role() = 'empresa' and company_id = own_company_id()));
revoke all on platform_gestors, company_memberships from authenticated;
grant select on platform_gestors, company_memberships to authenticated;

drop policy companies_update on companies;
create policy companies_update on companies for update to authenticated
  using (is_gestor()) with check (is_gestor());

drop policy courses_select on courses;
create policy courses_select on courses for select to authenticated using (
  is_gestor() or (context_role() = 'funcionario' and exists (
    select 1 from assignments a where a.course_id = courses.id and a.released
      and a.company_id = own_company_id())));
drop policy modules_select on modules;
create policy modules_select on modules for select to authenticated using (
  is_gestor() or (context_role() = 'funcionario' and exists (
    select 1 from assignments a where a.course_id = modules.course_id and a.released
      and a.company_id = own_company_id())));
drop policy lessons_select on lessons;
create policy lessons_select on lessons for select to authenticated using (
  is_gestor() or (context_role() = 'funcionario' and exists (
    select 1 from modules m join assignments a on a.course_id = m.course_id
    where m.id = lessons.module_id and a.released
      and a.company_id = own_company_id())));

drop policy progress_insert on lesson_progress;
drop policy progress_update on lesson_progress;
drop policy progress_delete on lesson_progress;
create policy progress_select on lesson_progress for select to authenticated using (
  is_gestor() or (company_id = own_company_id() and
    (context_role() = 'empresa' or
      (context_role() = 'funcionario' and user_id = auth.uid()))));
create policy progress_insert on lesson_progress for insert to authenticated with check (
  context_role() = 'funcionario' and user_id = auth.uid()
  and company_id = own_company_id() and exists (
    select 1 from lessons l join modules m on m.id = l.module_id
    join assignments a on a.course_id = m.course_id
    where l.id = lesson_id and a.company_id = lesson_progress.company_id
      and a.released));
create policy progress_update on lesson_progress for update to authenticated
  using (context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = own_company_id())
  with check (context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = own_company_id() and exists (
      select 1 from lessons l join modules m on m.id = l.module_id
      join assignments a on a.course_id = m.course_id
      where l.id = lesson_id and a.company_id = lesson_progress.company_id
        and a.released));
create policy progress_delete on lesson_progress for delete to authenticated
  using (is_gestor());

create policy certificates_select on certificates for select to authenticated using (
  is_gestor() or (company_id = own_company_id() and
    (context_role() = 'empresa' or
      (context_role() = 'funcionario' and user_id = auth.uid()))));
drop policy redemptions_select on redemptions;
create policy redemptions_select on redemptions for select to authenticated using (
  is_gestor() or (context_role() = 'funcionario' and user_id = auth.uid()
    and company_id = own_company_id()));
drop policy rewards_select on rewards;
create policy rewards_select on rewards for select to authenticated
  using (active and (is_gestor() or context_role() = 'funcionario'));
drop policy fcm_tokens_all on fcm_tokens;
create policy fcm_tokens_all on fcm_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function redeem_reward(p_reward uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare cost int; earned int; spent int; cid uuid := public.own_company_id();
begin
  if public.context_role() <> 'funcionario' or cid is null then
    raise exception 'Employee context required';
  end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text || cid::text));
  select points_cost into cost from public.rewards where id = p_reward and active;
  if not found then raise exception 'Reward unavailable'; end if;
  select coalesce(sum(l.points), 0) into earned from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id
    where lp.user_id = auth.uid() and lp.company_id = cid and lp.status = 'completed';
  select coalesce(sum(r.points_cost), 0) into spent from public.redemptions d
    join public.rewards r on r.id = d.reward_id
    where d.user_id = auth.uid() and d.company_id = cid;
  if earned - spent < cost then raise exception 'Insufficient points'; end if;
  insert into public.redemptions(user_id, company_id, reward_id)
  values (auth.uid(), cid, p_reward);
end $$;

-- Report views execute as their owner because managers cannot read course
-- contents. Every view therefore explicitly gates company scope and role.
create view completion_by_company as
select c.id as company_id, c.name as company,
  round(100.0 * count(*) filter (where lp.status = 'completed')
    / nullif(count(*), 0), 1) as pct
from companies c
join company_memberships cm on cm.company_id = c.id and cm.role = 'funcionario'
join assignments a on a.company_id = c.id and a.released
join modules m on m.course_id = a.course_id
join lessons l on l.module_id = m.id
left join lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
  and lp.company_id = c.id
where is_gestor() or (context_role() = 'empresa' and c.id = own_company_id())
group by c.id;
create view completion_by_dept as
select cm.company_id, cm.dept as department,
  round(100.0 * count(*) filter (where lp.status = 'completed')
    / nullif(count(*), 0), 1) as pct
from company_memberships cm
join assignments a on a.company_id = cm.company_id and a.released
join modules m on m.course_id = a.course_id
join lessons l on l.module_id = m.id
left join lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
  and lp.company_id = cm.company_id
where cm.role = 'funcionario' and (is_gestor() or
  (context_role() = 'empresa' and cm.company_id = own_company_id()))
group by cm.company_id, cm.dept;
create view engagement_monthly as
select company_id, date_trunc('month', updated_at)::date as month,
  count(distinct user_id) as active_users, count(*) as events
from lesson_progress where is_gestor() or
  (context_role() = 'empresa' and company_id = own_company_id())
group by 1, 2;
create view popular_content as
select lp.company_id, c.title as course,
  count(*) filter (where lp.status = 'completed') as completions
from courses c join modules m on m.course_id = c.id
join lessons l on l.module_id = m.id
join lesson_progress lp on lp.lesson_id = l.id
where is_gestor() or (context_role() = 'empresa' and lp.company_id = own_company_id())
group by lp.company_id, c.title;

create function ranking(p_company uuid, p_limit int default 20)
returns table(full_name text, dept text, points bigint)
language plpgsql stable security definer set search_path = '' as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  if not (public.is_gestor() or
    (public.context_role() in ('empresa', 'funcionario') and
      p_company = public.own_company_id())) then
    raise exception 'Forbidden';
  end if;
  return query
  select p.full_name, cm.dept,
    (coalesce((select sum(l.points) from public.lesson_progress lp
      join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = p.id and lp.company_id = p_company
        and lp.status = 'completed'), 0)
    - coalesce((select sum(r.points_cost) from public.redemptions d
      join public.rewards r on r.id = d.reward_id
      where d.user_id = p.id and d.company_id = p_company), 0))::bigint
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  order by 3 desc limit lim;
end $$;
revoke all on function ranking(uuid, int) from public, anon;
grant execute on function ranking(uuid, int) to authenticated;
grant select on completion_by_company, completion_by_dept,
  engagement_monthly, popular_content to authenticated;

-- Company manager dashboard: individual completion, without lesson content.
create function employee_completion(p_company uuid)
returns table(user_id uuid, full_name text, email text, dept text,
  job_title text, pct numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id())) then
    raise exception 'Forbidden';
  end if;
  return query
  select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title,
    round(100.0 * count(*) filter (where lp.status = 'completed')
      / nullif(count(*), 0), 1)
  from public.company_memberships cm
  join public.profiles p on p.id = cm.user_id
  left join public.assignments a on a.company_id = cm.company_id and a.released
  left join public.modules m on m.course_id = a.course_id
  left join public.lessons l on l.module_id = m.id
  left join public.lesson_progress lp on lp.lesson_id = l.id
    and lp.user_id = cm.user_id and lp.company_id = cm.company_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  group by cm.user_id, p.id, cm.dept, cm.job_title
  order by p.full_name limit 50;
end $$;
revoke all on function employee_completion(uuid) from public, anon;
grant execute on function employee_completion(uuid) to authenticated;

create function pending_invites()
returns table(email text, role text, company_id uuid, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select mi.email, mi.role, mi.company_id, mi.expires_at
  from public.membership_invites mi
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
  order by mi.created_at desc limit 50
$$;
revoke all on function pending_invites() from public, anon;
grant execute on function pending_invites() to authenticated;
