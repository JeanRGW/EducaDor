-- Run only against an isolated local database; all fixtures roll back.
begin;
insert into auth.users(id,email) values ('a9000000-0000-4000-8000-000000000001','prefix@example.test');
insert into profiles(id,full_name,email) values ('a9000000-0000-4000-8000-000000000001','Prefix','prefix@example.test');
insert into platform_gestors(user_id) values ('a9000000-0000-4000-8000-000000000001');
insert into companies(id,name) values ('b9000000-0000-4000-8000-000000000001','Company');
do $$ begin
  if (select code_prefix from companies where id='b9000000-0000-4000-8000-000000000001') <> 'EDU' then
    raise exception 'New company default changed';
  end if;
end $$;
update companies set code_prefix='legacy-prefix-too-long' where id='b9000000-0000-4000-8000-000000000001';
insert into company_memberships(user_id,company_id,role) values
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','empresa'),
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','funcionario');
insert into courses(id,title,all_companies) values
 ('c9000000-0000-4000-8000-000000000001','Old',true),
 ('c9000000-0000-4000-8000-000000000002','New',true);
insert into modules(id,course_id,title,position) values
 ('d9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Module',1),
 ('d9000000-0000-4000-8000-000000000002','c9000000-0000-4000-8000-000000000002','Module',1);
insert into lessons(id,module_id,title,kind,video_id,position) values
 ('e9000000-0000-4000-8000-000000000001','d9000000-0000-4000-8000-000000000001','Lesson','video','abcdefghijk',1),
 ('e9000000-0000-4000-8000-000000000002','d9000000-0000-4000-8000-000000000002','Lesson','video','abcdefghijk',1);
insert into lesson_progress(user_id,company_id,lesson_id,status)
 select 'a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001',id,'completed'
 from lessons where id::text like 'e9000000%';
insert into certificates(user_id,company_id,course_id,code) values
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','EDU-OLD123');
create function pg_temp.expect_error(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlerrm=expected then return; end if;
    raise;
  end;
  raise exception 'Expected error % from %',expected,statement;
end $$;
-- Auth session rows: the application guard rejects tokens without a live session.
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('f9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001',now(),now(),now()+interval '24 hours')
 on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"f9000000-0000-4000-8000-000000000001"}',true);
select pg_temp.expect_error('select update_company(''b9000000-0000-4000-8000-000000000001'',''{"name":"Company","code_prefix":"ABC"}'')','Forbidden');
select select_context('empresa','b9000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select update_company(''b9000000-0000-4000-8000-000000000001'',''{"name":"Company","code_prefix":"ABC"}'')','Forbidden');
select select_context('funcionario','b9000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select update_company(''b9000000-0000-4000-8000-000000000001'',''{"name":"Company","code_prefix":"ABC"}'')','Forbidden');
select select_context('gestor');
select update_company('b9000000-0000-4000-8000-000000000001','{"name":"Metadata only"}');
do $$ declare invalid jsonb; begin
  if (select code_prefix from companies where id='b9000000-0000-4000-8000-000000000001') <> 'legacy-prefix-too-long' then
    raise exception 'Omitted prefix changed historical value';
  end if;
  foreach invalid in array array['null'::jsonb,'""','"lower"','"A-B"','"A B"','"ÁBC"','" ABC"','"ABCDEFGHIJKLM"','123','true','[]','{}'] loop
    perform pg_temp.expect_error(format('select update_company(%L,%L::jsonb)',
      'b9000000-0000-4000-8000-000000000001',jsonb_build_object('name','Invalid','code_prefix',invalid)), 'Invalid certificate prefix');
  end loop;
  if (select code_prefix from companies where id='b9000000-0000-4000-8000-000000000001') <> 'legacy-prefix-too-long' then
    raise exception 'Invalid edit mutated prefix';
  end if;
end $$;
select update_company('b9000000-0000-4000-8000-000000000001','{"name":"Company","code_prefix":"A"}');
select update_company('b9000000-0000-4000-8000-000000000001','{"name":"Company","code_prefix":"ABC123DEF456"}');
select update_company('b9000000-0000-4000-8000-000000000001','{"name":"Company"}');
do $$ begin
  if (select code_prefix from companies where id='b9000000-0000-4000-8000-000000000001') <> 'ABC123DEF456' then
    raise exception 'Valid prefix not persisted/preserved';
  end if;
end $$;
select select_context('funcionario','b9000000-0000-4000-8000-000000000001');
reset role;
set local role service_role;
select issue_employee_certificate('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001');
select issue_employee_certificate('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000002');
reset role;
do $$ begin
  if (select code from certificates where course_id='c9000000-0000-4000-8000-000000000001') <> 'EDU-OLD123' then
    raise exception 'Existing certificate code rewritten';
  end if;
  if (select code from certificates where course_id='c9000000-0000-4000-8000-000000000002') !~ '^ABC123DEF456-[0-9A-HJKMNP-TV-Z]{6}$' then
    raise exception 'New certificate did not use updated prefix';
  end if;
  if (select count(*) from certificates where company_id='b9000000-0000-4000-8000-000000000001') <> 2 then
    raise exception 'Issuer idempotency changed';
  end if;
end $$;
rollback;
