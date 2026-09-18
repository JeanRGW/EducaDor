-- EducaDor foundation: RLS, RPC, views. Spec: stack/01-backend.md
-- No table triggers by decision (push/certificates are app-invoked functions).
-- The custom_access_token_hook below is login-time claim minting, not a trigger:
-- after creating it, enable it in Dashboard > Auth > Hooks > Custom Access Token.
-- Self-hosted: GOTRUE_HOOK_CUSTOM_ACCESS_TOKEN_URI=pg-functions://postgres/public/custom_access_token_hook
-- Role/company changes take effect on next login (claims are minted at issuance).

-- ---- caller identity helpers (JWT claims minted by the hook) ----
create or replace function is_gestor()
returns bool language sql stable as $$
  select (auth.jwt()->>'user_role') = 'gestor'
$$;

create or replace function own_company_id()
returns uuid language sql stable as $$
  select case
    when auth.jwt()->>'company_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then (auth.jwt()->>'company_id')::uuid
  end
$$;

-- Mint user_role + company_id into the JWT at login.
-- NOTE: top-level "role" is reserved (PostgREST SET ROLE from it) and cannot be
-- overridden via hooks – hence "user_role". Never rename back to "role".
create or replace function custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  r text;
  c uuid;
  claims jsonb;
begin
  select p.role, p.company_id into r, c
  from profiles p where p.id = (event->>'user_id')::uuid;
  claims := coalesce(event->'claims', '{}'::jsonb);
  if r is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(r));
    if c is not null then
      claims := jsonb_set(claims, '{company_id}', to_jsonb(c::text));
    end if;
  end if;
  return jsonb_set(event, '{claims}', claims);
end $$;
revoke all on function custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function custom_access_token_hook(jsonb) to supabase_auth_admin;

-- ---- companies ----
alter table companies enable row level security;
create policy companies_select on companies for select using (
  is_gestor() or id = own_company_id());
create policy companies_insert on companies for insert
  with check (is_gestor());
create policy companies_update on companies for update using (
  is_gestor() or id = own_company_id())
  with check (is_gestor() or id = own_company_id());
create policy companies_delete on companies for delete using (is_gestor());

-- ---- profiles: role/company_id frozen for non-gestor (no self-promotion) ----
alter table profiles enable row level security;
create policy profiles_select on profiles for select using (
  is_gestor() or id = auth.uid() or company_id = own_company_id());
create policy profiles_insert on profiles for insert with check (
  is_gestor()
  or (role = 'funcionario' and company_id = own_company_id() and id <> auth.uid())
  or (role = 'funcionario' and id = auth.uid() and company_id is null));
create policy profiles_update on profiles for update using (
  is_gestor() or id = auth.uid() or company_id = own_company_id())
  with check (
  is_gestor() or id = auth.uid() or company_id = own_company_id());
-- role/company_id are grant-frozen below (REVOKE UPDATE col): app roles can edit
-- names/phones/etc. but never reassign identity; only service-role functions do.

-- ---- catalog: readable iff released to the caller's company; writes gestor-only ----
alter table courses enable row level security;
create policy courses_select on courses for select using (
  is_gestor() or exists (
    select 1 from assignments a
    where a.course_id = courses.id and a.released
      and a.company_id = own_company_id()));
create policy courses_write on courses for all using (is_gestor())
  with check (is_gestor());

alter table modules enable row level security;
create policy modules_select on modules for select using (
  is_gestor() or exists (
    select 1 from assignments a
    where a.course_id = modules.course_id and a.released
      and a.company_id = own_company_id()));
create policy modules_write on modules for all using (is_gestor())
  with check (is_gestor());

alter table lessons enable row level security;
create policy lessons_select on lessons for select using (
  is_gestor() or exists (
    select 1 from modules m join assignments a on a.course_id = m.course_id
    where m.id = lessons.module_id and a.released
      and a.company_id = own_company_id()));
create policy lessons_write on lessons for all using (is_gestor())
  with check (is_gestor());

alter table assignments enable row level security;
create policy assignments_select on assignments for select using (
  is_gestor() or company_id = own_company_id());
create policy assignments_write on assignments for all using (is_gestor())
  with check (is_gestor());

-- ---- progress: split per operation (DELETE checks USING only, so it stays gestor-only) ----
alter table lesson_progress enable row level security;
create policy progress_select on lesson_progress for select using (
  is_gestor()
  or user_id = auth.uid()
  or own_company_id() = (select company_id from profiles where id = lesson_progress.user_id));
create policy progress_insert on lesson_progress for insert
  with check (is_gestor() or user_id = auth.uid());
create policy progress_update on lesson_progress for update using (
  is_gestor() or user_id = auth.uid())
  with check (is_gestor() or user_id = auth.uid());
create policy progress_delete on lesson_progress for delete using (is_gestor());

-- ---- certificates / rewards / redemptions / tokens ----
alter table certificates enable row level security;
create policy certificates_select on certificates for select using (
  is_gestor()
  or user_id = auth.uid()
  or own_company_id() = (select company_id from profiles where id = certificates.user_id));
-- inserts only via service-role (issue-certificate function): no client insert policy

alter table rewards enable row level security;
create policy rewards_select on rewards for select to authenticated using (active);
create policy rewards_write on rewards for all using (is_gestor())
  with check (is_gestor());

alter table redemptions enable row level security;
create policy redemptions_select on redemptions for select using (
  is_gestor() or user_id = auth.uid());
-- NO client insert policy: redemptions are minted only by redeem_reward() below

alter table fcm_tokens enable row level security;
create policy fcm_tokens_all on fcm_tokens for all using (
  is_gestor() or user_id = auth.uid())
  with check (user_id = auth.uid());
-- reads for sending push use the service-role key (bypasses RLS) inside push-on-assign

-- ---- storage.objects ----
create policy storage_public_read on storage.objects for select
  using (bucket_id = 'educador-public');
create policy storage_public_write on storage.objects for insert
  with check (bucket_id = 'educador-public' and is_gestor());
create policy storage_public_update on storage.objects for update using (
  bucket_id = 'educador-public' and is_gestor())
  with check (bucket_id = 'educador-public' and is_gestor());
create policy storage_public_delete on storage.objects for delete using (
  bucket_id = 'educador-public' and is_gestor());
-- educador-private / educador-backups have NO client policies:
-- all access via signed URLs minted by functions (server S3 keys bypass RLS)

-- ---- atomic redemption (advisory lock; SECURITY DEFINER since clients hold no insert right) ----
create or replace function redeem_reward(p_reward uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  cost int;
  earned int;
  spent int;
begin
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select points_cost into cost from rewards where id = p_reward and active;
  if not found then raise exception 'reward unavailable'; end if;
  select coalesce(sum(l.points), 0) into earned
  from lesson_progress p join lessons l on l.id = p.lesson_id
  where p.user_id = auth.uid() and p.status = 'completed';
  select coalesce(sum(r.points_cost), 0) into spent
  from redemptions d join rewards r on r.id = d.reward_id
  where d.user_id = auth.uid();
  if earned - spent < cost then raise exception 'insufficient points'; end if;
  insert into redemptions (user_id, reward_id) values (auth.uid(), p_reward);
end $$;
revoke all on function redeem_reward(uuid) from public, anon;
grant execute on function redeem_reward(uuid) to authenticated;

-- ---- reports (views/RPC, CSV export client-side) ----
-- security_invoker: plain views run as owner (bypass RLS); invoker mode enforces it
create or replace view completion_by_company with (security_invoker = true) as
select co.name as company,
  round(100.0 * count(*) filter (where lp.status = 'completed')
    / nullif(count(*), 0), 1) as pct
from companies co
join profiles p on p.company_id = co.id and p.role = 'funcionario'
join assignments a on a.company_id = co.id and a.released
join modules m on m.course_id = a.course_id
join lessons l on l.module_id = m.id
left join lesson_progress lp on lp.lesson_id = l.id and lp.user_id = p.id
group by co.name;

create or replace view completion_by_dept with (security_invoker = true) as
select p.company_id, p.dept as department,
  round(100.0 * count(*) filter (where lp.status = 'completed')
    / nullif(count(*), 0), 1) as pct
from profiles p
join assignments a on a.company_id = p.company_id and a.released
join modules m on m.course_id = a.course_id
join lessons l on l.module_id = m.id
left join lesson_progress lp on lp.lesson_id = l.id and lp.user_id = p.id
where p.role = 'funcionario'
group by p.company_id, p.dept;

create or replace view engagement_monthly with (security_invoker = true) as
select date_trunc('month', updated_at)::date as month,
  count(distinct user_id) as active_users,
  count(*) as events
from lesson_progress
group by 1 order by 1;

create or replace view popular_content with (security_invoker = true) as
select c.title as course,
  count(*) filter (where lp.status = 'completed') as completions
from courses c
join modules m on m.course_id = c.id
join lessons l on l.module_id = m.id
left join lesson_progress lp on lp.lesson_id = l.id
group by c.title order by completions desc;

create or replace function ranking(p_company uuid, p_limit int default 20)
returns table (full_name text, dept text, points bigint)
-- security definer so the redemptions subquery sees all rows (RLS would scope it
-- to the caller); tenancy is enforced by the guard below instead.
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  if not (is_gestor() or p_company = own_company_id()) then
    raise exception 'forbidden';
  end if;
  return query
  select p.full_name, p.dept,
    (coalesce((select sum(l.points) from lesson_progress lp
       join lessons l on l.id = lp.lesson_id
       where lp.user_id = p.id and lp.status = 'completed'), 0)
     - coalesce((select sum(r.points_cost) from redemptions d
       join rewards r on r.id = d.reward_id
       where d.user_id = p.id), 0))::bigint as points
  from profiles p
  where p.company_id = p_company and p.role = 'funcionario'
  order by points desc
  limit lim;
end $$;
revoke all on function ranking(uuid, int) from public, anon;
grant execute on function ranking(uuid, int) to authenticated;

-- ---- grants: PostgREST needs table grants; RLS does the real enforcement ----
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select on completion_by_company, completion_by_dept,
  engagement_monthly, popular_content to authenticated;
grant execute on function is_gestor() to authenticated;
grant execute on function own_company_id() to authenticated;
revoke all on function is_gestor() from public, anon;
revoke all on function own_company_id() from public, anon;
-- identity freeze: app roles (incl. gestor sessions) cannot UPDATE role/company_id;
-- reassignments go through service-role admin functions only (bypasses grants+RLS)
revoke update (role, company_id) on profiles from authenticated;
-- NOTE: repeat the table/sequence grants in later migrations that add tables.
