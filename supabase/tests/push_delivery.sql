begin;
insert into auth.users(id,email) values
 ('a9000000-0000-4000-8000-000000000001','push-a@example.test'),('a9000000-0000-4000-8000-000000000002','push-b@example.test'),
 ('a9000000-0000-4000-8000-000000000003','push-c@example.test'),('a9000000-0000-4000-8000-000000000004','push-d@example.test');
insert into profiles(id,full_name,email) select id, email, email from auth.users where email like 'push-%@example.test';
insert into companies(id,name) values ('b9000000-0000-4000-8000-000000000001','A'),('b9000000-0000-4000-8000-000000000002','B');
insert into platform_gestors values ('a9000000-0000-4000-8000-000000000001');
insert into company_memberships(user_id,company_id,role) values
 ('a9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','funcionario'),
 ('a9000000-0000-4000-8000-000000000003','b9000000-0000-4000-8000-000000000002','funcionario'),
 ('a9000000-0000-4000-8000-000000000004','b9000000-0000-4000-8000-000000000001','empresa');
insert into courses(id,title,status,all_companies) values ('c9000000-0000-4000-8000-000000000001','Test','paused',false);
insert into assignments(course_id,company_id,released,company_enabled) values
 ('c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001',true,true),
 ('c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000002',false,true);
insert into fcm_tokens(user_id,token) values ('a9000000-0000-4000-8000-000000000002','a'),('a9000000-0000-4000-8000-000000000003','b');
-- Auth session rows: the application guard rejects tokens without a live session.
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('f9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001',now(),now(),now()+interval '24 hours'),
 ('f9000000-0000-4000-8000-000000000002','a9000000-0000-4000-8000-000000000002',now(),now(),now()+interval '24 hours'),
 ('f9000000-0000-4000-8000-000000000004','a9000000-0000-4000-8000-000000000004',now(),now(),now()+interval '24 hours')
 on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"f9000000-0000-4000-8000-000000000001"}',true);
select select_context('gestor',null);
reset role;
set local role service_role;
do $$ declare r jsonb; begin
 r := claim_push_recipients('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','course_available','c9000000-0000-4000-8000-000000000001',null,null);
 if not (r->>'suppressed')::boolean then raise exception 'Platform paused accepted'; end if;
end $$;
reset role;
set local role authenticated;
do $$ declare c_all uuid; c_private uuid; c_first uuid; result jsonb; begin
 c_all := publish_video_trail('All','desc','Module','abcdefghijk',true);
 c_private := publish_video_trail('Private','desc','Module','abcdefghijk',false,array['b9000000-0000-4000-8000-000000000001'::uuid]);
 c_first := create_content_course('First');
 perform set_course_audience(c_first,false,array['b9000000-0000-4000-8000-000000000001'::uuid]);
 perform set_course_platform_enabled(c_first,true);
 -- Service-only claim is tested after leaving the client role.
 perform set_config('test.push_all',c_all::text,true);
 perform set_config('test.push_private',c_private::text,true);
 perform set_config('test.push_first',c_first::text,true);
end $$;
select set_course_platform_enabled('c9000000-0000-4000-8000-000000000001',true);
reset role;
set local role service_role;
do $$ declare result jsonb; c uuid; setting text; begin
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','course_available','c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000002',null);
 if not (result->>'suppressed')::boolean then raise exception 'Unassigned audience accepted'; end if;
 foreach setting in array array['test.push_all','test.push_private','test.push_first'] loop
  c := current_setting(setting)::uuid;
  result := claim_push_recipients('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','course_available',c,null,null);
  if (result->>'suppressed')::boolean or jsonb_array_length(result->'tokens') <> (case when setting='test.push_all' then 2 else 1 end) then raise exception 'Initial publication incorrect % %',setting,result; end if;
  if setting <> 'test.push_all' and result->'tokens'->0->>'token' <> 'a' then raise exception 'Wrong company notified'; end if;
 end loop;
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','course_available','c9000000-0000-4000-8000-000000000001',null,null);
 if jsonb_array_length(result->'tokens') <> 1 or result->'tokens'->0->>'token' <> 'a' then raise exception 'Audience gates failed %',result; end if;
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000001','course_available','c9000000-0000-4000-8000-000000000001',null,null);
 if (result->>'suppressed')::boolean is not true then raise exception 'Repeat claim accepted'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000004","session_id":"f9000000-0000-4000-8000-000000000004"}',true);
select select_context('empresa','b9000000-0000-4000-8000-000000000001');
select set_course_company_enabled('c9000000-0000-4000-8000-000000000001',false);
reset role;
set local role service_role;
do $$ declare r jsonb; begin
 r := claim_push_recipients('a9000000-0000-4000-8000-000000000004','f9000000-0000-4000-8000-000000000004','course_available','c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001',null);
 if not (r->>'suppressed')::boolean then raise exception 'Company paused accepted'; end if;
end $$;
reset role;
set local role authenticated;
select set_course_company_enabled('c9000000-0000-4000-8000-000000000001',true);
reset role;
set local role service_role;
do $$ declare result jsonb; begin
 begin perform claim_push_recipients('a9000000-0000-4000-8000-000000000004','f9000000-0000-4000-8000-000000000004','course_available','c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000002',null); raise exception 'cross-company accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000004','f9000000-0000-4000-8000-000000000004','course_available','c9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001',null);
 if jsonb_array_length(result->'tokens') <> 1 then raise exception 'Resume missing'; end if;
end $$;
reset role;
insert into certificates(id,user_id,company_id,course_id,code) values ('d9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','TEST-PUSH');
insert into notification_preferences(user_id,push_enabled) values ('a9000000-0000-4000-8000-000000000002',false);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002","session_id":"f9000000-0000-4000-8000-000000000002"}',true);
select select_context('funcionario','b9000000-0000-4000-8000-000000000001');
reset role;
set local role service_role;
do $$ declare result jsonb; begin
 begin perform claim_push_recipients('a9000000-0000-4000-8000-000000000004','f9000000-0000-4000-8000-000000000004','certificate_issued',null,null,'d9000000-0000-4000-8000-000000000001'); raise exception 'foreign certificate accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000002','f9000000-0000-4000-8000-000000000002','certificate_issued',null,null,'d9000000-0000-4000-8000-000000000001');
 if jsonb_array_length(result->'tokens') <> 0 then raise exception 'disabled preference delivered'; end if;
 result := claim_push_recipients('a9000000-0000-4000-8000-000000000002','f9000000-0000-4000-8000-000000000002','certificate_issued',null,null,'d9000000-0000-4000-8000-000000000001');
 if (result->>'suppressed')::boolean is not true then raise exception 'repeat certificate accepted'; end if;
end $$;
reset role;
rollback;
