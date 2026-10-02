-- Run after all migrations on an isolated PostgreSQL database. Fixtures roll back.
begin;
do $$ declare signature text; begin
  foreach signature in array array['public.gestor_dashboard()',
    'public.gestor_companies(text,boolean,integer)', 'public.gestor_completion(integer)',
    'public.gestor_activity_report(date,date)', 'public.pending_invites_page(text,uuid)'] loop
    if has_function_privilege('anon', signature, 'EXECUTE') or
      not has_function_privilege('authenticated', signature, 'EXECUTE') then
      raise exception 'Incorrect function grants: %', signature;
    end if;
  end loop;
end $$;
insert into auth.users(id, email, created_at) values
  ('a1000000-0000-4000-8000-000000000001', 'gestor-data@example.test', now() - interval '2 months'),
  ('a1000000-0000-4000-8000-000000000002', 'gestor-employee@example.test', now() - interval '1 month');
insert into profiles(id, full_name, email) values
  ('a1000000-0000-4000-8000-000000000001', 'Multi Role', 'gestor-data@example.test'),
  ('a1000000-0000-4000-8000-000000000002', 'Employee', 'gestor-employee@example.test');
insert into platform_gestors(user_id) values ('a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","session_id":"f1000000-0000-4000-8000-000000000001","user_role":"gestor"}', true);
do $$ declare command text; begin
  foreach command in array array['select gestor_dashboard()', 'select gestor_companies()',
    'select gestor_completion()', 'select gestor_activity_report(''2026-09-01'',''2026-09-30'')'] loop
    begin
      execute command;
      raise exception 'Missing context accepted';
    exception when raise_exception then
      if sqlerrm <> 'Forbidden' then raise; end if;
    end;
  end loop;
end $$;
select select_context('gestor');
do $$ declare d jsonb; begin
  d := gestor_dashboard();
  if (d->>'company_count')::int <> 0 or d->>'completion_pct' is not null or
    d->'activities' <> '[]'::jsonb or jsonb_array_length(d->'growth') <> 6 or
    gestor_completion() <> '[]'::jsonb or gestor_companies()->'items' <> '[]'::jsonb then
    raise exception 'Empty states fabricated data';
  end if;
end $$;
reset role;
insert into companies(id, name, active, created_at) values
  ('b1000000-0000-4000-8000-000000000001', 'Literal %_ Company', true, now() - interval '2 months'),
  ('b1000000-0000-4000-8000-000000000002', 'Literal %_ Company', false, now() - interval '1 month');
insert into company_memberships(user_id, company_id, role) values
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'empresa'),
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'funcionario'),
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'funcionario'),
  ('a1000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000001', 'funcionario');
insert into courses(id, title, all_companies) values
  ('c1000000-0000-4000-8000-000000000001', 'Same title', true),
  ('c1000000-0000-4000-8000-000000000002', 'Same title', false);
insert into assignments(course_id, company_id) values
  ('c1000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000001');
insert into modules(id, course_id, title) values
  ('d1000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'All'),
  ('d1000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'Selected');
insert into lessons(id, module_id, title, kind) values
  ('e1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'One', 'reading'),
  ('e1000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001', 'Two', 'reading'),
  ('e1000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000002', 'Three', 'reading');
insert into lesson_progress(user_id, company_id, lesson_id, status, updated_at) values
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001', 'completed', '2026-09-01T03:00:00Z'),
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000001', 'completed', '2026-10-01T02:59:59Z'),
  ('a1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000002', 'in_progress', '2026-09-01T02:59:59Z'),
  ('a1000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000002', 'in_progress', '2026-09-20T12:00:00Z'),
  ('a1000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000003', 'completed', '2026-10-01T03:00:00Z');
insert into membership_invites(email, role, company_id, token_hash, expires_at) values
  ('pending@example.test', 'empresa', 'b1000000-0000-4000-8000-000000000002', repeat('c',64), now() + interval '1 hour');
set local role authenticated;
do $$ declare d jsonb; r jsonb; p jsonb; before_completion jsonb; begin
  d := gestor_dashboard();
  if (d->>'user_count')::int <> 2 or (d->>'completion_pct')::numeric <> 37.5 or
    jsonb_array_length(d->'activities') <> 7 then
    raise exception 'Identity deduplication/weighted completion/activity failed: %', d;
  end if;
  r := gestor_activity_report('2026-09-01', '2026-09-30');
  if (r->'engagement'->0->>'active_users')::int <> 2 or
    jsonb_array_length(r->'popular_content') <> 1 or
    (r->'popular_content'->0->>'completions')::int <> 2 then
    raise exception 'São Paulo boundaries/global engagement deduplication failed: %', r;
  end if;
  before_completion := gestor_completion();
  r := gestor_activity_report('2026-10-01', '2026-10-31');
  if (r->'popular_content'->0->>'course_id')::uuid <> 'c1000000-0000-4000-8000-000000000002' or
    gestor_completion() <> before_completion then
    raise exception 'Activity period changed current completion';
  end if;
  r := gestor_activity_report('2026-07-01', '2026-10-31');
  if jsonb_array_length(r->'engagement') <> 4 or
    (r->'engagement'->0->>'active_users')::int <> 0 or
    jsonb_array_length(r->'popular_content') <> 2 then
    raise exception 'Zero filling/course ID grouping failed';
  end if;
  r := gestor_activity_report('2020-01-01', '2020-01-31');
  if r->'popular_content' <> '[]'::jsonb or
    (r->'engagement'->0->>'active_users')::int <> 0 then raise exception 'Empty period fabricated data'; end if;
  begin
    perform gestor_activity_report('2026-09-30', '2026-09-01');
    raise exception 'Reversed period accepted';
  exception when raise_exception then if sqlerrm <> 'Invalid period' then raise; end if; end;
  begin
    perform gestor_activity_report('2020-01-01', '2026-01-01');
    raise exception 'Unbounded period accepted';
  exception when raise_exception then if sqlerrm <> 'Invalid period' then raise; end if; end;
  p := gestor_companies('%_', true);
  if jsonb_array_length(p->'items') <> 1 or (p->>'active_count')::int <> 1 or
    (p->>'inactive_count')::int <> 1 or (p->'items'->0->>'employee_count')::int <> 2 then
    raise exception 'Literal search/status/counts failed: %', p;
  end if;
  if (select company_name from pending_invites_page('empresa')) <> 'Literal %_ Company' or
    exists(select 1 from pending_invites_page('gestor')) then raise exception 'Scoped invite names/filter failed'; end if;
  perform set_course_platform_enabled('c1000000-0000-4000-8000-000000000001', false);
  if (gestor_dashboard()->>'completion_pct')::numeric <> 37.5 then raise exception 'Pause erased completion'; end if;
end $$;

select select_context('empresa', 'b1000000-0000-4000-8000-000000000001');
do $$ declare command text; begin
  foreach command in array array['select gestor_dashboard()', 'select gestor_companies()',
    'select gestor_completion()', 'select gestor_activity_report(''2026-09-01'',''2026-09-30'')'] loop
    begin execute command; raise exception 'Company context accepted platform RPC';
    exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  end loop;
  if exists(select 1 from pending_invites_page()) then raise exception 'Company manager saw foreign invite'; end if;
end $$;
select select_context('funcionario', 'b1000000-0000-4000-8000-000000000001');
do $$ begin
  begin perform gestor_dashboard(); raise exception 'Employee context accepted platform RPC';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  if exists(select 1 from pending_invites_page()) then raise exception 'Employee saw invitations'; end if;
end $$;
reset role;
insert into companies(name) select 'Page ' || lpad(n::text, 3, '0') from generate_series(1,52) n;
update lesson_progress set updated_at = now() - interval '1 day';
set local role authenticated;
select select_context('gestor');
do $$ declare d jsonb; begin
  if jsonb_array_length(gestor_companies()->'items') <> 50 or
    jsonb_array_length(gestor_companies('',null,50)->'items') <> 4 or
    jsonb_array_length(gestor_completion()) <> 50 or
    jsonb_array_length(gestor_completion(50)) <> 4 then raise exception 'Pagination failed'; end if;
  if gestor_companies('no matches')->'items' <> '[]'::jsonb then raise exception 'Search did not filter'; end if;
  d := gestor_dashboard();
  if jsonb_array_length(d->'activities') <> 10 then raise exception 'Activity limit failed'; end if;
  if (d->>'active_user_count')::int <> 2 or
    (d->'growth'->5->>'users')::int <> 2 or
    (d->'growth'->5->>'companies')::int <> 54 or
    (d->>'new_company_count')::int < 52 then
    raise exception 'Growth/rolling distinct activity failed: %', d;
  end if;
  if (select count(*) from jsonb_array_elements(gestor_completion(50)) r where r->>'pct' is null) <> 4 then
    raise exception 'No-data companies were converted to zero';
  end if;
end $$;
reset role;
delete from platform_gestors where user_id = 'a1000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
  begin perform gestor_dashboard(); raise exception 'Revoked grant accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
rollback;
