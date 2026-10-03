-- Run on an isolated database after all migrations. All fixtures roll back.
begin;
do $$ declare signature text; begin
  foreach signature in array array['public.company_dashboard(uuid)', 'public.company_employees(uuid,text,integer)'] loop
    if has_function_privilege('anon', signature, 'EXECUTE') or
      not has_function_privilege('authenticated', signature, 'EXECUTE') then
      raise exception 'Incorrect RPC grants: %', signature;
    end if;
  end loop;
end $$;
insert into auth.users(id, email) values
  ('a3000000-0000-4000-8000-000000000001', 'company-manager@example.test'),
  ('a3000000-0000-4000-8000-000000000002', 'company-employee@example.test');
insert into profiles(id, full_name, email) values
  ('a3000000-0000-4000-8000-000000000001', 'Ana %_ Silva', 'company-manager@example.test'),
  ('a3000000-0000-4000-8000-000000000002', 'Bruno', 'company-employee@example.test');
insert into companies(id, name) values
  ('b3000000-0000-4000-8000-000000000001', 'Company A'),
  ('b3000000-0000-4000-8000-000000000002', 'Company B'),
  ('b3000000-0000-4000-8000-000000000003', 'Empty company');
insert into platform_gestors(user_id) values ('a3000000-0000-4000-8000-000000000001');
insert into company_memberships(user_id, company_id, role, dept) values
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'empresa', null),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'funcionario', 'RH'),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 'empresa', null),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 'funcionario', 'TI'),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000003', 'empresa', null),
  ('a3000000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-000000000001', 'funcionario', 'TI');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-4000-8000-000000000001","session_id":"f3000000-0000-4000-8000-000000000001","user_role":"empresa","company_id":"b3000000-0000-4000-8000-000000000001"}', true);
do $$ begin
  begin perform company_dashboard('b3000000-0000-4000-8000-000000000001'); raise exception 'Legacy claims accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
select select_context('empresa', 'b3000000-0000-4000-8000-000000000001');
do $$ declare d jsonb; p jsonb; begin
  d := company_dashboard('b3000000-0000-4000-8000-000000000001');
  p := company_employees('b3000000-0000-4000-8000-000000000001');
  if (d->>'employee_count')::int <> 2 or (d->>'active_course_count')::int <> 0 or
    (d->>'certificate_count')::int <> 0 or d->>'completion_pct' is not null or
    d->'highlights' <> '[]'::jsonb or jsonb_array_length(d->'engagement') <> 6 or
    exists(select 1 from jsonb_array_elements(d->'engagement') m where (m->>'active_users')::int <> 0) or
    p->'items'->0->>'pct' is not null then raise exception 'No-data state fabricated results'; end if;
end $$;
reset role;
insert into courses(id, title, all_companies, status) values
  ('c3000000-0000-4000-8000-000000000001', 'Global', true, 'released'),
  ('c3000000-0000-4000-8000-000000000002', 'Only A', false, 'released'),
  ('c3000000-0000-4000-8000-000000000003', 'Company paused', true, 'released'),
  ('c3000000-0000-4000-8000-000000000004', 'Platform paused', true, 'paused'),
  ('c3000000-0000-4000-8000-000000000005', 'No audience', false, 'released');
insert into assignments(course_id, company_id, released, company_enabled) values
  ('c3000000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-000000000001', true, true),
  ('c3000000-0000-4000-8000-000000000003', 'b3000000-0000-4000-8000-000000000001', false, false);
insert into modules(id, course_id, title)
  select c.id, c.id, 'Sensitive module' from courses c where c.id::text like 'c3000000%';
insert into lessons(id, module_id, title, kind)
  select c.id, c.id, 'Sensitive lesson', 'reading' from courses c where c.id::text like 'c3000000%';
insert into lesson_progress(user_id, company_id, lesson_id, status, updated_at) values
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000001', 'completed',
    ((date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '1 month') at time zone 'America/Sao_Paulo') - interval '1 second'),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000002', 'completed',
    ((date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '1 month') at time zone 'America/Sao_Paulo')),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000004', 'in_progress',
    ((date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '1 month') at time zone 'America/Sao_Paulo') + interval '1 day'),
  ('a3000000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000003', 'in_progress', now() - interval '1 second'),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 'c3000000-0000-4000-8000-000000000001', 'completed', now());
insert into certificates(user_id, company_id, course_id, code) values
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000001', 'TEST-A'),
  ('a3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 'c3000000-0000-4000-8000-000000000001', 'TEST-B');
set local role authenticated;
do $$ declare d jsonb; p jsonb; begin
  d := company_dashboard('b3000000-0000-4000-8000-000000000001');
  p := company_employees('b3000000-0000-4000-8000-000000000001');
  if (d->>'employee_count')::int <> 2 or (d->>'active_course_count')::int <> 2 or
    (d->>'certificate_count')::int <> 1 or (d->>'completion_pct')::numeric <> 25 or
    (d->'highlights'->0->>'pct')::numeric <> 50 or
    (d->'engagement'->3->>'active_users')::int <> 1 or
    (d->'engagement'->4->>'active_users')::int <> 1 or
    (d->'engagement'->5->>'active_users')::int <> 1 then raise exception 'Company aggregates/gates/timezone failed: %', d; end if;
  if (p->>'total_count')::int <> 2 or (p->'items'->0->>'pct')::numeric <> 50 or
    (p->'items'->1->>'pct')::numeric <> 0 or
    (p->'items'->0->>'last_activity_at')::timestamptz >= date_trunc('month', now()) then
    raise exception 'Other-company activity leaked or progress lost: %', p;
  end if;
  if (company_employees('b3000000-0000-4000-8000-000000000001', '%_')->>'filtered_count')::int <> 1 or
    (company_employees('b3000000-0000-4000-8000-000000000001', ' ti ')->>'filtered_count')::int <> 1 or
    company_employees('b3000000-0000-4000-8000-000000000001', 'no match')->'items' <> '[]'::jsonb then
    raise exception 'Literal name/department search failed';
  end if;
  if exists(select 1 from lessons) then raise exception 'Manager read lesson contents'; end if;
  begin perform company_dashboard('b3000000-0000-4000-8000-000000000002'); raise exception 'Inactive company context accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform company_employees('b3000000-0000-4000-8000-000000000002'); raise exception 'Foreign employee query accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  perform set_course_company_enabled('c3000000-0000-4000-8000-000000000001', false);
  d := company_dashboard('b3000000-0000-4000-8000-000000000001');
  if (d->>'active_course_count')::int <> 1 or (d->>'completion_pct')::numeric <> 25 or
    (d->>'certificate_count')::int <> 1 then raise exception 'Pause erased progress/certificates'; end if;
end $$;
select select_context('empresa', 'b3000000-0000-4000-8000-000000000002');
do $$ declare d jsonb; begin
  d := company_dashboard('b3000000-0000-4000-8000-000000000002');
  if (d->>'employee_count')::int <> 1 or (d->>'certificate_count')::int <> 1 or
    (d->>'completion_pct')::numeric <> 33.3 then raise exception 'Company switch mixed progress: %', d; end if;
end $$;
select select_context('empresa', 'b3000000-0000-4000-8000-000000000003');
do $$ declare d jsonb; begin
  d := company_dashboard('b3000000-0000-4000-8000-000000000003');
  if (d->>'employee_count')::int <> 0 or d->>'completion_pct' is not null or
    company_employees('b3000000-0000-4000-8000-000000000003')->'items' <> '[]'::jsonb then raise exception 'Empty company failed'; end if;
end $$;
select select_context('funcionario', 'b3000000-0000-4000-8000-000000000001');
do $$ begin
  begin perform company_dashboard('b3000000-0000-4000-8000-000000000001'); raise exception 'Employee role accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform company_employees('b3000000-0000-4000-8000-000000000001'); raise exception 'Employee directory access accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
select select_context('gestor');
do $$ begin
  begin perform company_dashboard('b3000000-0000-4000-8000-000000000001'); raise exception 'Platform role accepted company RPC';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
insert into auth.users(id, email) select md5('company-data-' || n)::uuid, 'page' || n || '@example.test' from generate_series(1,52) n;
insert into profiles(id, full_name, email)
  select md5('company-data-' || n)::uuid, 'Same name', 'page' || n || '@example.test' from generate_series(1,52) n;
insert into company_memberships(user_id, company_id, role, dept)
  select md5('company-data-' || n)::uuid, 'b3000000-0000-4000-8000-000000000001', 'funcionario', 'Operations' from generate_series(1,52) n;
insert into lesson_progress(user_id, company_id, lesson_id, status)
  select (select p.id from profiles p where p.full_name = 'Same name' order by p.id desc limit 1),
    'b3000000-0000-4000-8000-000000000001', l.id, 'completed'
  from lessons l join modules m on m.id = l.module_id
  where public.course_company_allowed(m.course_id, 'b3000000-0000-4000-8000-000000000001');
set local role authenticated;
select select_context('empresa', 'b3000000-0000-4000-8000-000000000001');
do $$ declare p jsonb; q jsonb; begin
  p := company_employees('b3000000-0000-4000-8000-000000000001');
  q := company_employees('b3000000-0000-4000-8000-000000000001', '', 50);
  if (p->>'total_count')::int <> 54 or jsonb_array_length(p->'items') <> 50 or jsonb_array_length(q->'items') <> 4 or
    (company_dashboard('b3000000-0000-4000-8000-000000000001')->>'employee_count')::int <> 54 or
    exists(select 1 from jsonb_array_elements(p->'items') x join jsonb_array_elements(q->'items') y on x->>'user_id' = y->>'user_id') then
    raise exception 'Exact counts/stable pagination failed'; end if;
  if jsonb_array_length(company_employees('b3000000-0000-4000-8000-000000000001', 'Operations', 50)->'items') <> 2 then
    raise exception 'Search was applied after pagination'; end if;
  if (company_dashboard('b3000000-0000-4000-8000-000000000001')->'highlights'->0->>'pct')::numeric <> 100 or
    not exists(select 1 from jsonb_array_elements(q->'items') i where (i->>'pct')::numeric = 100) then
    raise exception 'Highlights only considered page one'; end if;
end $$;
reset role;
delete from company_memberships where user_id = 'a3000000-0000-4000-8000-000000000001'
  and company_id = 'b3000000-0000-4000-8000-000000000001' and role = 'empresa';
set local role authenticated;
do $$ begin
  begin perform company_dashboard('b3000000-0000-4000-8000-000000000001'); raise exception 'Revoked manager accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
update companies set active = false where id = 'b3000000-0000-4000-8000-000000000002';
-- The membership still exists, but its previously selected context is no longer valid.
update session_contexts set company_id = 'b3000000-0000-4000-8000-000000000002'
  where session_id = 'f3000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
  begin perform company_employees('b3000000-0000-4000-8000-000000000002'); raise exception 'Inactive company accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
rollback;
