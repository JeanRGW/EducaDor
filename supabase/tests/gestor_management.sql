-- Run on an isolated database after all migrations, using privileged psql.
begin;
insert into auth.users(id, email) values
  ('a2000000-0000-4000-8000-000000000001', 'gestor-one@example.test'),
  ('a2000000-0000-4000-8000-000000000002', 'gestor-two@example.test');
insert into profiles(id, full_name, email) values
  ('a2000000-0000-4000-8000-000000000001', 'Gestor One', 'gestor-one@example.test'),
  ('a2000000-0000-4000-8000-000000000002', 'Gestor Two', 'gestor-two@example.test');
insert into platform_gestors(user_id) select id from profiles where id::text like 'a2000000%';
insert into companies(id, name) values
  ('b2000000-0000-4000-8000-000000000001', 'Company One'),
  ('b2000000-0000-4000-8000-000000000002', 'Company Two');
insert into company_memberships(user_id, company_id, role) values
  ('a2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 'empresa'),
  ('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001', 'empresa'),
  ('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 'empresa'),
  ('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001', 'funcionario');
insert into courses(id, title, status, all_companies, responsible_id) values
  ('c2000000-0000-4000-8000-000000000001', 'Original course', 'paused', false,
   'a2000000-0000-4000-8000-000000000002');
insert into modules(id, course_id, title, position) values
  ('d2000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', 'Original module', 1);
insert into lessons(id, module_id, title, kind, video_id, points, position) values
  ('e2000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001',
    'Original lesson', 'video', 'dQw4w9WgXcQ', 25, 1);
insert into assignments(course_id, company_id, released, company_enabled) values
  ('c2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', true, false);
insert into lesson_progress(user_id, company_id, lesson_id, status, position_sec) values
  ('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001', 'completed', 123);
insert into certificates(user_id, company_id, course_id, code) values
  ('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001', 'TEST-MANAGEMENT');
insert into session_contexts(session_id, user_id, role, company_id) values
  ('f2000000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000002', 'gestor', null),
  ('f2000000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-000000000002', 'empresa',
    'b2000000-0000-4000-8000-000000000001');

create function pg_temp.expect_error(statement text, expected text)
returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlerrm = expected then return; end if;
    raise;
  end;
  raise exception 'Expected error % from %', expected, statement;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000001","session_id":"f2000000-0000-4000-8000-000000000001"}', true);

-- A platform grant without an active gestor context is not enough.
select pg_temp.expect_error('select set_company_active(''b2000000-0000-4000-8000-000000000001'', false)', 'Forbidden');
select select_context('empresa', 'b2000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select gestor_managers()', 'Forbidden');
select pg_temp.expect_error('select gestor_course_lessons(''c2000000-0000-4000-8000-000000000001'')', 'Forbidden');
select pg_temp.expect_error('select gestor_course_audience(''c2000000-0000-4000-8000-000000000001'')', 'Forbidden');
select pg_temp.expect_error('select update_company(''b2000000-0000-4000-8000-000000000001'', ''{"name":"Illegal"}'')', 'Forbidden');
select pg_temp.expect_error('select revoke_gestor_access(''a2000000-0000-4000-8000-000000000002'')', 'Forbidden');
select pg_temp.expect_error('select update_course_metadata(''c2000000-0000-4000-8000-000000000001'', ''Illegal'', '''', null, null)', 'Forbidden');
select pg_temp.expect_error('select update_course_lesson(''e2000000-0000-4000-8000-000000000001'', ''Illegal'', ''Illegal'', ''dQw4w9WgXcQ'')', 'Forbidden');
select select_context('gestor');
select pg_temp.expect_error('select update_company(''b2000000-0000-4000-8000-000000000001'', ''{"name":""}'')', 'Invalid company');
select pg_temp.expect_error('select update_course_lesson(''e2000000-0000-4000-8000-000000000001'', ''Module'', ''Lesson'', ''bad'')', 'Invalid lesson');

select update_company('b2000000-0000-4000-8000-000000000001',
  '{"name":"Edited company","cnpj":"123","email":"contact@example.test","state":"mg"}');
select set_company_active('b2000000-0000-4000-8000-000000000001', false);
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000002","session_id":"f2000000-0000-4000-8000-000000000003"}', true);
do $$ begin
  if context_role() is not null then raise exception 'Paused company retained access'; end if;
end $$;
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000001","session_id":"f2000000-0000-4000-8000-000000000001"}', true);
select set_company_active('b2000000-0000-4000-8000-000000000001', true);
select update_own_profile('Edited Name', '12345', '1990-01-01', 'Edited address');
select update_course_metadata('c2000000-0000-4000-8000-000000000001',
  'Edited course', 'Edited description', 'covers/test.webp', 'a2000000-0000-4000-8000-000000000002');
select update_course_lesson('e2000000-0000-4000-8000-000000000001', 'Edited module', 'Edited lesson', 'abcdefghijk');
select pg_temp.expect_error('select update_own_profile(''Name'', '''', current_date + 1, '''')', 'Invalid profile');
do $$ begin
  if (select title from gestor_course_lessons('c2000000-0000-4000-8000-000000000001')) <> 'Edited lesson' then
    raise exception 'Lesson detail RPC failed'; end if;
  if (select all_companies from gestor_course_audience('c2000000-0000-4000-8000-000000000001')) then
    raise exception 'Audience RPC returned the wrong scope'; end if;
  if (select company_ids from gestor_course_audience('c2000000-0000-4000-8000-000000000001'))
    <> array['b2000000-0000-4000-8000-000000000001'::uuid] then
    raise exception 'Audience RPC missed the released company'; end if;
  if (select name from companies where id = 'b2000000-0000-4000-8000-000000000001') <> 'Edited company' or
     (select state from companies where id = 'b2000000-0000-4000-8000-000000000001') <> 'MG' then
    raise exception 'Company edits not persisted'; end if;
  if (select full_name from profiles where id = auth.uid()) <> 'Edited Name' or
     (select email from profiles where id = auth.uid()) <> 'gestor-one@example.test' or
     (select full_name from profiles where id = 'a2000000-0000-4000-8000-000000000002') <> 'Gestor Two' then
    raise exception 'Profile edits changed another identity or Auth email'; end if;
  if (select status from courses where id = 'c2000000-0000-4000-8000-000000000001') <> 'paused' or
     (select all_companies from courses where id = 'c2000000-0000-4000-8000-000000000001') or
     (select company_enabled from assignments where course_id = 'c2000000-0000-4000-8000-000000000001') or
     not (select released from assignments where course_id = 'c2000000-0000-4000-8000-000000000001') then
    raise exception 'Course editing changed access preferences'; end if;
  if (select points from lessons where id = 'e2000000-0000-4000-8000-000000000001') <> 25 or
     (select video_id from lessons where id = 'e2000000-0000-4000-8000-000000000001') <> 'abcdefghijk' or
     (select position_sec from lesson_progress where lesson_id = 'e2000000-0000-4000-8000-000000000001') <> 123 or
     (select status from lesson_progress where lesson_id = 'e2000000-0000-4000-8000-000000000001') <> 'completed' or
     not exists (select 1 from certificates where code = 'TEST-MANAGEMENT') then
    raise exception 'Course editing reset learning state'; end if;
  if (select count(*) from gestor_managers(null, 'TWO', 0)) <> 1 or
     (select count(*) from gestor_managers('b2000000-0000-4000-8000-000000000001')) <> 2 then
    raise exception 'Manager search/scope failed'; end if;
end $$;
select revoke_gestor_access('a2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select revoke_gestor_access(''a2000000-0000-4000-8000-000000000001'', ''b2000000-0000-4000-8000-000000000001'')', 'Last company gestor');
select revoke_gestor_access('a2000000-0000-4000-8000-000000000002');
select pg_temp.expect_error('select revoke_gestor_access(''a2000000-0000-4000-8000-000000000001'')', 'Last platform gestor');
-- A previously responsible gestor can remain credited after grant revocation.
select update_course_metadata('c2000000-0000-4000-8000-000000000001',
  'Edited again', '', 'covers/test.webp', 'a2000000-0000-4000-8000-000000000002');
reset role;
do $$ begin
  if not exists (select 1 from company_memberships where user_id = 'a2000000-0000-4000-8000-000000000002'
    and company_id = 'b2000000-0000-4000-8000-000000000001' and role = 'funcionario') or
    not exists (select 1 from company_memberships where user_id = 'a2000000-0000-4000-8000-000000000002'
    and company_id = 'b2000000-0000-4000-8000-000000000002' and role = 'empresa') or
    exists (select 1 from session_contexts where user_id = 'a2000000-0000-4000-8000-000000000002') then
    raise exception 'Revocation scope or selected-session cleanup failed'; end if;
  if has_function_privilege('authenticated', 'accept_membership_invite(text, uuid, text)', 'execute') or
    has_function_privilege('anon', 'revoke_gestor_access(uuid, uuid)', 'execute') then
    raise exception 'Privileged operation exposed'; end if;
end $$;

insert into membership_invites(email, role, token_hash, expires_at) values
  ('gestor-two@example.test', 'gestor', repeat('2', 64), now() + interval '1 hour');
set local role service_role;
select accept_membership_invite(repeat('2', 64), 'a2000000-0000-4000-8000-000000000002', 'gestor-two@example.test');
select pg_temp.expect_error('select accept_membership_invite(repeat(''2'',64), ''a2000000-0000-4000-8000-000000000002'', ''gestor-two@example.test'')', 'Invitation unavailable');
reset role;
do $$ begin
  if not exists (select 1 from platform_gestors where user_id = 'a2000000-0000-4000-8000-000000000002') or
    exists (select 1 from membership_invites where token_hash = repeat('2', 64)) then
    raise exception 'Invitation grant/consumption was not atomic'; end if;
end $$;
-- Search and pagination are applied in SQL, not after a client-side first page.
insert into auth.users(id, email)
  select ('a2200000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid,
    'page-' || i || '@example.test' from generate_series(1,51) i;
insert into profiles(id, full_name, email)
  select id, 'Pagination ' || email, email from auth.users where id::text like 'a2200000%';
insert into platform_gestors(user_id) select id from profiles where id::text like 'a2200000%';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000001","session_id":"f2000000-0000-4000-8000-000000000001"}', true);
do $$ begin
  if (select count(*) from gestor_managers(null, 'Pagination', 0)) <> 50 or
    (select count(*) from gestor_managers(null, 'Pagination', 50)) <> 1 or
    (select count(*) from gestor_managers(null, '%', 0)) <> 0 then
    raise exception 'Manager pagination or literal search failed'; end if;
end $$;
rollback;
