-- Lifecycle operations use the active DB context, never a client-supplied role.
create function public.update_company(p_company uuid, p_fields jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or
    length(trim(coalesce(p_fields->>'name', ''))) not between 1 and 200 or
    exists (select 1 from jsonb_each_text(p_fields) f where length(f.value) > 500) or
    (coalesce(p_fields->>'email', '') <> '' and
      p_fields->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'Invalid company';
  end if;
  update public.companies set name = trim(p_fields->>'name'),
    cnpj = nullif(trim(p_fields->>'cnpj'), ''),
    responsible = nullif(trim(p_fields->>'responsible'), ''),
    email = nullif(trim(p_fields->>'email'), ''),
    phone = nullif(trim(p_fields->>'phone'), ''),
    address = nullif(trim(p_fields->>'address'), ''),
    city = nullif(trim(p_fields->>'city'), ''),
    state = nullif(upper(trim(p_fields->>'state')), ''),
    field = nullif(trim(p_fields->>'field'), '')
    where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
end $$;

create function public.set_company_active(p_company uuid, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_active is null then raise exception 'Invalid company'; end if;
  update public.companies set active = p_active where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
  -- Pauses retain grants, progress and the selected contexts for reactivation.
end $$;

create function public.gestor_managers(p_company uuid default null,
  p_search text default '', p_offset integer default 0)
returns table(id uuid, full_name text, email text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then
    raise exception 'Invalid page';
  end if;
  return query select p.id, p.full_name, p.email from public.profiles p
    where (case when p_company is null then exists (
      select 1 from public.platform_gestors g where g.user_id = p.id)
    else exists (select 1 from public.company_memberships m
      where m.user_id = p.id and m.company_id = p_company and m.role = 'empresa') end)
    and (strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0 or
      strpos(lower(p.email), lower(coalesce(p_search, ''))) > 0)
    order by p.full_name, p.id limit 50 offset p_offset;
end $$;

create function public.revoke_gestor_access(p_user uuid, p_company uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_company is null then
    -- Serialize removals and grant writes; two simultaneous removals cannot
    -- each observe the other gestor and leave the platform without one.
    lock table public.platform_gestors in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.platform_gestors where user_id = p_user) then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.platform_gestors) <= 1 then
      raise exception 'Last platform gestor';
    end if;
    delete from public.platform_gestors where user_id = p_user;
    delete from public.session_contexts where user_id = p_user and role = 'gestor';
  else
    -- Also serialize against platform revocations while checking the caller.
    lock table public.platform_gestors in share mode;
    lock table public.company_memberships in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa') then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.company_memberships
      where company_id = p_company and role = 'empresa') <= 1 then
      raise exception 'Last company gestor';
    end if;
    delete from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa';
    delete from public.session_contexts
      where user_id = p_user and company_id = p_company and role = 'empresa';
  end if;
  delete from public.membership_invites where lower(email) = (
    select lower(email) from public.profiles where id = p_user)
    and role = case when p_company is null then 'gestor' else 'empresa' end
    and company_id is not distinct from p_company;
  -- Identity, employee memberships, other companies and course authorship stay.
end $$;

-- Invitation acceptance and revocation share a lock order. A request that read
-- an invitation before revocation must not recreate the revoked grant later.
create function public.accept_membership_invite(p_token_hash text, p_user uuid, p_email text)
returns void language plpgsql security definer set search_path = '' as $$
declare invite public.membership_invites;
begin
  lock table public.platform_gestors in share row exclusive mode;
  lock table public.company_memberships in share row exclusive mode;
  select * into invite from public.membership_invites
    where token_hash = p_token_hash and lower(email) = lower(p_email)
      and expires_at > now() for update;
  if not found or not exists (select 1 from public.profiles
    where id = p_user and lower(email) = lower(p_email)) then
    raise exception 'Invitation unavailable';
  end if;
  if invite.company_id is not null and not exists (
    select 1 from public.companies where id = invite.company_id and active) then
    raise exception 'Company unavailable';
  end if;
  if invite.role = 'gestor' then
    insert into public.platform_gestors(user_id) values (p_user) on conflict do nothing;
  else
    insert into public.company_memberships(user_id, company_id, role, dept, job_title)
      values (p_user, invite.company_id, invite.role, invite.dept, invite.job_title)
      on conflict (user_id, company_id, role) do update
        set dept = excluded.dept, job_title = excluded.job_title;
  end if;
  delete from public.membership_invites where id = invite.id;
end $$;
revoke all on function public.accept_membership_invite(text, uuid, text) from public, anon, authenticated;
grant execute on function public.accept_membership_invite(text, uuid, text) to service_role;

create function public.update_own_profile(p_name text, p_phone text,
  p_birth_date date, p_address text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 200 or
    length(coalesce(p_phone, '')) > 50 or length(coalesce(p_address, '')) > 500 or
    p_birth_date > current_date then raise exception 'Invalid profile'; end if;
  update public.profiles set full_name = trim(p_name),
    phone = nullif(trim(p_phone), ''), birth_date = p_birth_date,
    address = nullif(trim(p_address), '') where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $$;

create function public.gestor_course_lessons(p_course uuid, p_offset integer default 0)
returns table(id uuid, title text, kind text, video_id text, module_title text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid page'; end if;
  if not exists (select 1 from public.courses where courses.id = p_course) then
    raise exception 'Course unavailable';
  end if;
  return query select l.id, l.title, l.kind, l.video_id, m.title
    from public.modules m join public.lessons l on l.module_id = m.id
    where m.course_id = p_course
    order by m.position, m.id, l.position, l.id limit 50 offset p_offset;
end $$;

create function public.gestor_course_audience(p_course uuid)
returns table(all_companies boolean, company_ids uuid[])
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if not exists (select 1 from public.courses where courses.id = p_course) then
    raise exception 'Course unavailable';
  end if;
  return query select c.all_companies,
    array(select a.company_id from public.assignments a
      where a.course_id = p_course and a.released order by a.company_id)
    from public.courses c where c.id = p_course;
end $$;

create function public.update_course_metadata(p_course uuid, p_title text,
  p_description text, p_cover_key text, p_responsible_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare existing public.courses;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 then raise exception 'Invalid course'; end if;
  if p_cover_key is distinct from existing.cover_key and p_cover_key is not null and
    (length(p_cover_key) > 200 or p_cover_key !~ '^covers/[A-Za-z0-9_-]{1,120}\.webp$') then
    raise exception 'Invalid cover';
  end if;
  if p_responsible_id is distinct from existing.responsible_id and
    p_responsible_id is not null and not exists (
      select 1 from public.platform_gestors where user_id = p_responsible_id) then
    raise exception 'Invalid responsible';
  end if;
  update public.courses set title = trim(p_title), description = coalesce(p_description, ''),
    cover_key = p_cover_key, responsible_id = p_responsible_id where id = p_course;
  -- Never replace rows or alter status, audience, company preferences or points.
end $$;

create function public.update_course_lesson(p_lesson uuid, p_module_title text,
  p_title text, p_video_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare existing public.lessons;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.lessons where id = p_lesson for update;
  if not found then raise exception 'Lesson unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    p_module_title is null or length(trim(p_module_title)) not between 1 and 200 or
    (existing.kind = 'video' and (p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$')) or
    (existing.kind <> 'video' and p_video_id is not null) then
    raise exception 'Invalid lesson';
  end if;
  update public.modules set title = trim(p_module_title) where id = existing.module_id;
  update public.lessons set title = trim(p_title),
    video_id = case when kind = 'video' then p_video_id else video_id end
    where id = p_lesson;
end $$;

revoke all on function public.update_company(uuid, jsonb), public.set_company_active(uuid, boolean),
  public.gestor_managers(uuid, text, integer), public.revoke_gestor_access(uuid, uuid),
  public.update_own_profile(text, text, date, text),
  public.gestor_course_lessons(uuid, integer),
  public.gestor_course_audience(uuid),
  public.update_course_metadata(uuid, text, text, text, uuid),
  public.update_course_lesson(uuid, text, text, text) from public, anon;
grant execute on function public.update_company(uuid, jsonb), public.set_company_active(uuid, boolean),
  public.gestor_managers(uuid, text, integer), public.revoke_gestor_access(uuid, uuid),
  public.update_own_profile(text, text, date, text),
  public.gestor_course_lessons(uuid, integer),
  public.gestor_course_audience(uuid),
  public.update_course_metadata(uuid, text, text, text, uuid),
  public.update_course_lesson(uuid, text, text, text) to authenticated;
