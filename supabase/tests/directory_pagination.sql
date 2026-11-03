begin;
insert into auth.users(id,email) select ('aa000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid, 'directory'||n||'@test.invalid' from generate_series(1,121) n;
insert into profiles(id,email,full_name) select id,email,case when email='directory121@test.invalid' then E'Literal %_\\ Person' else 'Same Name' end from auth.users where email like 'directory%@test.invalid';
insert into platform_gestors(user_id) select id from profiles where email like 'directory%@test.invalid';
insert into companies(id,name) values ('bb000000-0000-4000-8000-000000000001','First'),('bb000000-0000-4000-8000-000000000002','Second');
insert into company_memberships(user_id,company_id,role) select id,'bb000000-0000-4000-8000-000000000001','empresa' from profiles where email like 'directory%@test.invalid';
insert into company_memberships(user_id,company_id,role) values ('aa000000-0000-4000-8000-000000000001','bb000000-0000-4000-8000-000000000001','funcionario');
insert into membership_invites(email,role,company_id,token_hash,expires_at) select email,'empresa','bb000000-0000-4000-8000-000000000001',lpad(row_number() over ()::text,64,'0'),now()+interval '1 day' from profiles where email like 'directory%@test.invalid';
insert into membership_invites(email,role,company_id,token_hash,expires_at) values ('other@test.invalid','empresa','bb000000-0000-4000-8000-000000000002',repeat('f',64),now()+interval '1 day'),('expired@test.invalid','empresa','bb000000-0000-4000-8000-000000000001',repeat('e',64),now()-interval '1 day');
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$ begin
  begin execute statement; exception when others then if sqlerrm=expected then return; end if; raise; end;
  raise exception 'Expected error %',expected;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","session_id":"cc000000-0000-4000-8000-000000000001"}',true);
select pg_temp.expect_error('select platform_professionals_page()','Forbidden');
select pg_temp.expect_error('select company_managers_page(''bb000000-0000-4000-8000-000000000001'')','Forbidden');
select pg_temp.expect_error('select directory_pending_invites()','Forbidden');
select select_context('gestor');
do $$ declare ids uuid[]; begin
  select array_agg(id) into ids from (select * from platform_professionals_page('',0) union all select * from platform_professionals_page('',50) union all select * from platform_professionals_page('',100)) pages;
  if cardinality(ids)<>121 or (select count(distinct id) from unnest(ids) id)<>121 then raise exception 'Professional pages overlap/incomplete'; end if;
  select array_agg(id) into ids from (select * from company_managers_page('bb000000-0000-4000-8000-000000000001','',0) union all select * from company_managers_page('bb000000-0000-4000-8000-000000000001','',50) union all select * from company_managers_page('bb000000-0000-4000-8000-000000000001','',100)) pages;
  if cardinality(ids)<>121 or (select count(distinct id) from unnest(ids) id)<>121 then raise exception 'Manager pages overlap/incomplete'; end if;
  if (select count(*) from platform_professionals_page())<>50 or (select count(*) from directory_pending_invites('empresa','bb000000-0000-4000-8000-000000000001','',100))<>21 then raise exception 'Page cap/offset failed'; end if;
  if (select count(*) from platform_professionals_page(E'%_\\'))<>1 or (select count(*) from company_managers_page('bb000000-0000-4000-8000-000000000001',E'%_\\'))<>1 or (select count(*) from directory_pending_invites(null,null,E'%_\\'))<>1 then raise exception 'Literal search failed'; end if;
end $$;
select pg_temp.expect_error('select platform_professionals_page('''',-1)','Invalid page');
select pg_temp.expect_error('select company_managers_page(null,repeat(''a'',201))','Invalid page');
select pg_temp.expect_error('select directory_pending_invites(null,null,'''',null)','Invalid page');
select select_context('empresa','bb000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select platform_professionals_page()','Forbidden');
select pg_temp.expect_error('select company_managers_page(''bb000000-0000-4000-8000-000000000002'')','Forbidden');
select pg_temp.expect_error('select revoke_gestor_access(''aa000000-0000-4000-8000-000000000002'')','Forbidden');
do $$ begin
  if (select count(*) from company_managers_page('bb000000-0000-4000-8000-000000000001'))<>50 or (select count(*) from directory_pending_invites('empresa',null,'',100))<>21 or exists(select 1 from directory_pending_invites(null,'bb000000-0000-4000-8000-000000000002')) then raise exception 'Company isolation failed'; end if;
end $$;
select select_context('funcionario','bb000000-0000-4000-8000-000000000001');
select pg_temp.expect_error('select directory_pending_invites()','Forbidden');
select pg_temp.expect_error('select company_managers_page(''bb000000-0000-4000-8000-000000000001'')','Forbidden');
reset role;
do $$ begin
  if has_function_privilege('anon','platform_professionals_page(text,integer)','execute') or has_function_privilege('anon','company_managers_page(uuid,text,integer)','execute') or has_function_privilege('anon','directory_pending_invites(text,uuid,text,integer)','execute') then raise exception 'Anonymous RPC exposed'; end if;
end $$;
rollback;
