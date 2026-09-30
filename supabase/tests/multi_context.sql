-- Run against an isolated local database after all migrations.
-- Creates its own fixture and rolls back. Requires a privileged psql session.
begin;
do $$
declare table_name text;
begin
  for table_name in
    select tablename from pg_tables where schemaname = 'public'
  loop
    if not has_table_privilege('service_role', 'public.' || quote_ident(table_name), 'SELECT')
      or not has_table_privilege('service_role', 'public.' || quote_ident(table_name), 'INSERT')
      or not has_table_privilege('service_role', 'public.' || quote_ident(table_name), 'UPDATE')
      or not has_table_privilege('service_role', 'public.' || quote_ident(table_name), 'DELETE') then
      raise exception 'Service role lacks access to %', table_name;
    end if;
  end loop;
end $$;
insert into auth.users(id, email) values
  ('a0000000-0000-4000-8000-000000000001', 'multi-role@example.test'),
  ('a0000000-0000-4000-8000-000000000002', 'other@example.test'),
  ('a0000000-0000-4000-8000-000000000003', 'person-a@example.test');
insert into companies(id, name) values
  ('b0000000-0000-4000-8000-000000000001', 'Company A'),
  ('b0000000-0000-4000-8000-000000000002', 'Company B');
insert into profiles(id, full_name, email) values
  ('a0000000-0000-4000-8000-000000000001', 'Multi Role', 'multi-role@example.test'),
  ('a0000000-0000-4000-8000-000000000002', 'Other User', 'other@example.test'),
  ('a0000000-0000-4000-8000-000000000003', 'Invited Person', 'Person-A@Example.test');
insert into platform_gestors(user_id) values
  ('a0000000-0000-4000-8000-000000000001');
insert into company_memberships(user_id, company_id, role) values
  ('a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001', 'empresa'),
  ('a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001', 'funcionario'),
  ('a0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002', 'funcionario'),
  ('a0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000002', 'funcionario');
insert into courses(id, title) values
  ('c0000000-0000-4000-8000-000000000001', 'Shared course');
insert into modules(id, course_id, title) values
  ('d0000000-0000-4000-8000-000000000001',
   'c0000000-0000-4000-8000-000000000001', 'Module');
insert into lessons(id, module_id, title, kind) values
  ('e0000000-0000-4000-8000-000000000001',
   'd0000000-0000-4000-8000-000000000001', 'Lesson', 'reading');
insert into assignments(course_id, company_id) values
  ('c0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000001'),
  ('c0000000-0000-4000-8000-000000000001',
   'b0000000-0000-4000-8000-000000000002');
insert into membership_invites(email, role, company_id, token_hash, expires_at)
values ('person-a@example.test', 'empresa',
    'b0000000-0000-4000-8000-000000000001', repeat('a', 64), now() + interval '1 hour'),
  ('person-b@example.test', 'empresa',
    'b0000000-0000-4000-8000-000000000002', repeat('b', 64), now() + interval '1 hour');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001", "session_id":"f0000000-0000-4000-8000-000000000001"}', true);
do $$ begin
  if (select count(*) from available_contexts()) <> 4 then
    raise exception 'Expected four contexts for one Auth identity';
  end if;
  if (select count(*) from courses) <> 0 then
    raise exception 'No selected context must not read courses';
  end if;
end $$;

select select_context('empresa', 'b0000000-0000-4000-8000-000000000001');
do $$ begin
  if (select count(*) from courses) <> 0 then
    raise exception 'Company manager may not read course content';
  end if;
  if (select count(*) from completion_by_company) <> 1 then
    raise exception 'Manager report must contain only its company';
  end if;
  if (select count(*) from pending_invites()) <> 1 then
    raise exception 'Manager saw another company invitation';
  end if;
  if (select full_name from pending_invites()) is distinct from 'Invited Person' then
    raise exception 'Pending invite must include the profile name with case-insensitive email matching';
  end if;
  if (select count(*) from employee_completion(
    'b0000000-0000-4000-8000-000000000001')) <> 1 then
    raise exception 'Manager must see only its company employees';
  end if;
  begin
    perform employee_completion('b0000000-0000-4000-8000-000000000002');
    raise exception 'Manager read another company report';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
  begin
    insert into lesson_progress(user_id, company_id, lesson_id)
    values ('a0000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000001',
      'e0000000-0000-4000-8000-000000000001');
    raise exception 'Manager was able to learn';
  exception when insufficient_privilege then null;
  end;
  begin
    perform select_context('empresa', 'b0000000-0000-4000-8000-000000000002');
    raise exception 'Manager selected a role not granted in company B';
  exception when raise_exception then
    if sqlerrm <> 'Context unavailable' then raise; end if;
  end;
  begin
    update profiles set email = 'promoted@example.test'
      where id = 'a0000000-0000-4000-8000-000000000001';
    raise exception 'Client updated identity email';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into platform_gestors(user_id)
    values ('a0000000-0000-4000-8000-000000000002');
    raise exception 'Client assigned a platform role';
  exception when insufficient_privilege then null;
  end;
end $$;

select select_context('gestor', null);
do $$ begin
  if (select count(*) from pending_invites()) <> 2 then
    raise exception 'Gestor must see both invitations';
  end if;
  if not exists (select 1 from pending_invites()
      where email = 'person-b@example.test' and full_name is null) then
    raise exception 'Invitation without a profile must still be returned';
  end if;
end $$;

select select_context('funcionario', 'b0000000-0000-4000-8000-000000000001');
insert into lesson_progress(user_id, company_id, lesson_id, status)
values ('a0000000-0000-4000-8000-000000000001',
  'b0000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-000000000001', 'completed');
do $$ begin
  if (select count(*) from lesson_progress) <> 1 then
    raise exception 'Employee progress not visible in company A';
  end if;
  if (select count(*) from pending_invites()) <> 0 then
    raise exception 'Employee saw management invitations';
  end if;
  begin
    insert into lesson_progress(user_id, company_id, lesson_id)
    values ('a0000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000002',
      'e0000000-0000-4000-8000-000000000001');
    raise exception 'Employee wrote to company B while in A';
  exception when insufficient_privilege then null;
  end;
end $$;

select select_context('funcionario', 'b0000000-0000-4000-8000-000000000002');
do $$ begin
  if (select count(*) from lesson_progress) <> 0 then
    raise exception 'Company A progress leaked into company B';
  end if;
  if (select points from ranking('b0000000-0000-4000-8000-000000000002')
    where full_name = 'Multi Role') <> 0 then
    raise exception 'Points crossed company boundary';
  end if;
end $$;

reset role;
delete from company_memberships where user_id =
  'a0000000-0000-4000-8000-000000000001'
  and company_id = 'b0000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  if (select count(*) from selected_context()) <> 0
    or (select count(*) from courses) <> 0 then
    raise exception 'Revoked membership retained its selected context';
  end if;
end $$;

select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-000000000001", "session_id":"f0000000-0000-4000-8000-000000000002"}', true);
do $$ begin
  if (select count(*) from selected_context()) <> 0 then
    raise exception 'Selection leaked across Auth sessions';
  end if;
end $$;
reset role;
rollback;
