-- Run after all migrations on an isolated database; fixture is rolled back.
begin;
do $$ begin
  if has_function_privilege('anon', 'public.content_catalog(text,text,integer,integer)', 'EXECUTE') or
    has_function_privilege('anon', 'public.employee_can_access_course(uuid)', 'EXECUTE') or
    has_function_privilege('anon', 'public.set_course_company_enabled(uuid,boolean)', 'EXECUTE') or
    has_function_privilege('authenticated', 'public.course_company_allowed(uuid,uuid)', 'EXECUTE') then
    raise exception 'Content function privileges are too broad';
  end if;
end $$;
insert into auth.users(id, email) values
  ('aa000000-0000-4000-8000-000000000001', 'content-owner@example.test'),
  ('aa000000-0000-4000-8000-000000000002', 'content-employee@example.test'),
  ('aa000000-0000-4000-8000-000000000003', 'content-manager-b@example.test');
insert into profiles(id, full_name, email) values
  ('aa000000-0000-4000-8000-000000000001', 'Owner', 'content-owner@example.test'),
  ('aa000000-0000-4000-8000-000000000002', 'Employee', 'content-employee@example.test'),
  ('aa000000-0000-4000-8000-000000000003', 'Manager B', 'content-manager-b@example.test');
insert into companies(id, name) values
  ('bb000000-0000-4000-8000-000000000001', 'Content Company A'),
  ('bb000000-0000-4000-8000-000000000002', 'Content Company B');
insert into platform_gestors(user_id) values ('aa000000-0000-4000-8000-000000000001');
insert into company_memberships(user_id, company_id, role) values
  ('aa000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000001', 'empresa'),
  ('aa000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000001', 'funcionario'),
  ('aa000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000002', 'funcionario'),
  ('aa000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000001', 'funcionario'),
  ('aa000000-0000-4000-8000-000000000003', 'bb000000-0000-4000-8000-000000000002', 'empresa');
insert into courses(id, title, all_companies) values
  ('cc000000-0000-4000-8000-000000000001', 'Selected content', false),
  ('cc000000-0000-4000-8000-000000000002', 'All companies content', true);
insert into assignments(course_id, company_id) values
  ('cc000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000001');
insert into modules(id, course_id, title) values
  ('dd000000-0000-4000-8000-000000000001', 'cc000000-0000-4000-8000-000000000001', 'Selected module'),
  ('dd000000-0000-4000-8000-000000000002', 'cc000000-0000-4000-8000-000000000002', 'All module');
insert into lessons(id, module_id, title, kind) values
  ('ee000000-0000-4000-8000-000000000001', 'dd000000-0000-4000-8000-000000000001', 'Selected lesson', 'reading'),
  ('ee000000-0000-4000-8000-000000000002', 'dd000000-0000-4000-8000-000000000002', 'All lesson', 'reading');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aa000000-0000-4000-8000-000000000001","session_id":"ff000000-0000-4000-8000-000000000001"}', true);
do $$ begin
  begin
    perform content_catalog();
    raise exception 'Catalog accepted a missing context';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
end $$;

select select_context('empresa', 'bb000000-0000-4000-8000-000000000001');
do $$ begin
  if (select count(*) from content_catalog()) <> 2 or
    exists (select 1 from content_catalog() where company_ids is not null or company_count <> 1) then
    raise exception 'Company metadata scope is incorrect';
  end if;
  if (select count(*) from courses) <> 0 or (select count(*) from lessons) <> 0 then
    raise exception 'Manager can learn';
  end if;
  begin
    perform set_course_platform_enabled('cc000000-0000-4000-8000-000000000002', false);
    raise exception 'Company manager changed platform status';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
  begin
    perform set_course_audience('cc000000-0000-4000-8000-000000000002', true);
    raise exception 'Company manager changed platform audience';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
  begin
    perform publish_video_trail('Unauthorized', '', 'Module', 'abcdefghijk');
    raise exception 'Company manager published content';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
end $$;

select select_context('funcionario', 'bb000000-0000-4000-8000-000000000001');
insert into lesson_progress(user_id, company_id, lesson_id, status) values
  ('aa000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000001',
   'ee000000-0000-4000-8000-000000000002', 'completed');
do $$ begin
  if (select count(*) from courses) <> 2 or (select count(*) from lessons) <> 2 then
    raise exception 'Employee cannot read eligible content';
  end if;
  begin
    perform set_course_company_enabled('cc000000-0000-4000-8000-000000000002', false);
    raise exception 'Employee changed company access';
  exception when raise_exception then
    if sqlerrm <> 'Forbidden' then raise; end if;
  end;
end $$;

select select_context('empresa', 'bb000000-0000-4000-8000-000000000001');
select set_course_company_enabled('cc000000-0000-4000-8000-000000000002', false);
do $$ begin
  if (select company_enabled from content_catalog()
    where id = 'cc000000-0000-4000-8000-000000000002') then
    raise exception 'Company pause was not persisted';
  end if;
  if (select pct from completion_by_company where company_id = own_company_id()) <> 25 then
    raise exception 'Pause changed historical completion';
  end if;
end $$;
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000001');
do $$ declare affected int; begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') or
    (select count(*) from courses) <> 1 or (select count(*) from modules) <> 1 or
    (select count(*) from lessons) <> 1 then raise exception 'Company pause did not block content'; end if;
  update lesson_progress set position_sec = 10
    where lesson_id = 'ee000000-0000-4000-8000-000000000002';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'Paused progress was writable'; end if;
  if (select count(*) from lesson_progress) <> 1 then raise exception 'Pause deleted progress'; end if;
  begin
    insert into lesson_progress(user_id, company_id, lesson_id)
    values (auth.uid(), own_company_id(), 'ee000000-0000-4000-8000-000000000002');
    raise exception 'Paused progress insert succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000002');
do $$ begin
  if not employee_can_access_course('cc000000-0000-4000-8000-000000000002') or
    employee_can_access_course('cc000000-0000-4000-8000-000000000001') then
    raise exception 'Company pause/allowlist leaked across company boundaries';
  end if;
end $$;

-- A second employee in the paused company is blocked by the same setting.
select set_config('request.jwt.claims',
  '{"sub":"aa000000-0000-4000-8000-000000000002","session_id":"ff000000-0000-4000-8000-000000000002"}', true);
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000001');
do $$ begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'Company pause did not apply to every employee';
  end if;
end $$;

-- Company B must not see A-only content or create an assignment for itself.
select set_config('request.jwt.claims',
  '{"sub":"aa000000-0000-4000-8000-000000000003","session_id":"ff000000-0000-4000-8000-000000000003"}', true);
select select_context('empresa', 'bb000000-0000-4000-8000-000000000002');
do $$ begin
  if (select count(*) from content_catalog()) <> 1 then raise exception 'Manager saw unassigned metadata'; end if;
  begin
    perform set_course_company_enabled('cc000000-0000-4000-8000-000000000001', true);
    raise exception 'Company manager granted itself content';
  exception when raise_exception then
    if sqlerrm <> 'Course unavailable' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claims',
  '{"sub":"aa000000-0000-4000-8000-000000000001","session_id":"ff000000-0000-4000-8000-000000000001"}', true);
select select_context('gestor', null);
select set_course_platform_enabled('cc000000-0000-4000-8000-000000000002', false);
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000002');
do $$ begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'Global pause did not block another company';
  end if;
end $$;
select select_context('empresa', 'bb000000-0000-4000-8000-000000000001');
select set_course_company_enabled('cc000000-0000-4000-8000-000000000002', true);
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000001');
do $$ begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'Company manager overrode the global pause';
  end if;
end $$;
select select_context('gestor', null);
select set_course_platform_enabled('cc000000-0000-4000-8000-000000000002', true);
select set_course_audience('cc000000-0000-4000-8000-000000000002', false,
  array['bb000000-0000-4000-8000-000000000001']::uuid[]);
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000002');
do $$ begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'Removed company retained access';
  end if;
end $$;
select select_context('empresa', 'bb000000-0000-4000-8000-000000000001');
select set_course_company_enabled('cc000000-0000-4000-8000-000000000002', false);
select select_context('gestor', null);
select set_course_audience('cc000000-0000-4000-8000-000000000002', false,
  array['bb000000-0000-4000-8000-000000000002']::uuid[]);
select set_course_audience('cc000000-0000-4000-8000-000000000002', true);
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000001');
do $$ begin
  if employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'Audience changes lost the company pause preference';
  end if;
end $$;

-- Newly registered companies inherit all-company eligibility without a fan-out insert.
reset role;
insert into companies(id, name) values ('bb000000-0000-4000-8000-000000000003', 'Future Company');
insert into company_memberships(user_id, company_id, role) values
  ('aa000000-0000-4000-8000-000000000001', 'bb000000-0000-4000-8000-000000000003', 'funcionario');
set local role authenticated;
select select_context('funcionario', 'bb000000-0000-4000-8000-000000000003');
do $$ begin
  if not employee_can_access_course('cc000000-0000-4000-8000-000000000002') then
    raise exception 'New company did not inherit all-company content';
  end if;
end $$;

select select_context('gestor', null);
do $$ declare created uuid; before_count int; begin
  if (select count(*) from content_catalog('SELECTED', 'course')) <> 1 or
    (select count(*) from content_catalog('', null, 1, 1)) <> 1 then
    raise exception 'Catalog search/filter/pagination is incorrect';
  end if;
  begin
    perform set_course_audience('cc000000-0000-4000-8000-000000000002', false, '{}');
    raise exception 'Empty allowlist accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invalid audience' then raise; end if;
  end;
  begin
    perform set_course_audience('cc000000-0000-4000-8000-000000000002', false,
      array['00000000-0000-4000-8000-000000000099']::uuid[]);
    raise exception 'Unknown company accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invalid audience' then raise; end if;
  end;
  created := publish_video_trail('YouTube trail', 'Description', 'Module', 'abcdefghijk');
  if not (select all_companies from courses where id = created) or
    (select count(*) from lessons l join modules m on m.id = l.module_id
      where m.course_id = created and l.video_provider = 'youtube' and l.video_id = 'abcdefghijk') <> 1 then
    raise exception 'Publishing did not create a real YouTube trail';
  end if;
  created := publish_video_trail('Covered trail', 'Description', 'Module', 'abcdefghijk',
    true, '{}', 'covers/abc123_test.webp', 'aa000000-0000-4000-8000-000000000001');
  if (select cover_key from courses where id = created) <> 'covers/abc123_test.webp' or
    (select responsible_id from courses where id = created) <>
      'aa000000-0000-4000-8000-000000000001' then
    raise exception 'Publishing did not store cover and responsible';
  end if;
  begin
    perform publish_video_trail('Bad cover', '', 'Module', 'abcdefghijk',
      true, '{}', 'private/evil.png', null);
    raise exception 'Invalid cover accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invalid cover' then raise; end if;
  end;
  begin
    perform publish_video_trail('Bad responsible', '', 'Module', 'abcdefghijk',
      true, '{}', null, 'aa000000-0000-4000-8000-000000000002');
    raise exception 'Non-gestor responsible accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invalid responsible' then raise; end if;
  end;
  select count(*) into before_count from courses;
  begin
    perform publish_video_trail('Rejected', '', 'Module', 'abcdefghijk', false, '{}');
    raise exception 'Invalid publish succeeded';
  exception when raise_exception then
    if sqlerrm <> 'Invalid audience' then raise; end if;
  end;
  if (select count(*) from courses) <> before_count then raise exception 'Partial publishing state survived'; end if;
end $$;
reset role;
rollback;
