-- Isolated database only; fixtures roll back. No production data is used.
begin;
do $$ declare signature text; begin
  foreach signature in array array['public.employee_summary(uuid)','public.employee_catalog(uuid,text,text,text,integer)',
    'public.employee_lessons(uuid,uuid,integer)','public.save_employee_progress(uuid,uuid,integer,boolean)',
    'public.employee_certificates(uuid,integer)','public.employee_ranking(uuid)','public.redeem_employee_reward(uuid,uuid)'] loop
    if has_function_privilege('anon',signature,'EXECUTE') or not has_function_privilege('authenticated',signature,'EXECUTE') then raise exception 'Incorrect grants: %',signature; end if;
  end loop;
  if has_function_privilege('authenticated','public.issue_employee_certificate(uuid,uuid,uuid,uuid)','EXECUTE') or
    not has_function_privilege('service_role','public.issue_employee_certificate(uuid,uuid,uuid,uuid)','EXECUTE') then raise exception 'Issuer grants too broad'; end if;
end $$;
insert into auth.users(id,email) values
 ('a7000000-0000-4000-8000-000000000001','learning-a@example.test'),('a7000000-0000-4000-8000-000000000002','learning-b@example.test');
insert into profiles(id,full_name,email) values
 ('a7000000-0000-4000-8000-000000000001','Ana','learning-a@example.test'),('a7000000-0000-4000-8000-000000000002','Bruno','learning-b@example.test');
insert into companies(id,name,code_prefix) values
 ('b7000000-0000-4000-8000-000000000001','Company A','AUD'),('b7000000-0000-4000-8000-000000000002','Company B','BUD');
insert into platform_gestors(user_id) values ('a7000000-0000-4000-8000-000000000001');
insert into company_memberships(user_id,company_id,role,dept) values
 ('a7000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','funcionario','RH'),
 ('a7000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','empresa',null),
 ('a7000000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000002','funcionario','TI'),
 ('a7000000-0000-4000-8000-000000000002','b7000000-0000-4000-8000-000000000001','funcionario','TI');
insert into courses(id,title,all_companies) values
 ('c7000000-0000-4000-8000-000000000001','Video %_ course',true),
 ('c7000000-0000-4000-8000-000000000002','Private quiz',false),
 ('c7000000-0000-4000-8000-000000000003','Empty',true);
insert into assignments(course_id,company_id) values ('c7000000-0000-4000-8000-000000000002','b7000000-0000-4000-8000-000000000001');
insert into modules(id,course_id,title,position) values
 ('d7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000001','Second module',2),
 ('d7000000-0000-4000-8000-000000000002','c7000000-0000-4000-8000-000000000001','First module',1),
 ('d7000000-0000-4000-8000-000000000003','c7000000-0000-4000-8000-000000000002','Quiz',1);
insert into lessons(id,module_id,title,kind,video_id,points,position) values
 ('e7000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000001','Last video','video','abcdefghijk',10,1),
 ('e7000000-0000-4000-8000-000000000002','d7000000-0000-4000-8000-000000000002','First video','video','abcdefghijk',10,1),
 ('e7000000-0000-4000-8000-000000000003','d7000000-0000-4000-8000-000000000003','Quiz','quiz',null,10,1);
insert into rewards(id,title,points_cost) values ('f7000000-0000-4000-8000-000000000001','Reward',15);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000001","session_id":"ff700000-0000-4000-8000-000000000001"}',true);
do $$ begin
  begin perform ranking('b7000000-0000-4000-8000-000000000001'); raise exception 'Missing context saw ranking'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform employee_summary('b7000000-0000-4000-8000-000000000001'); raise exception 'Missing context saw summary'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
select select_context('funcionario','b7000000-0000-4000-8000-000000000001');
do $$ declare result jsonb; begin
 result := employee_summary(own_company_id());
 if (result->>'course_count')::int <> 3 or (result->>'completed_course_count')::int <> 0 or (result->>'balance')::int <> 0 or result->>'department' <> 'RH'
   or jsonb_array_length(result->'activity') <> 7 then raise exception 'Summary fabricated data: %',result; end if;
 if (employee_catalog(own_company_id(),'%_')->>'total')::int <> 1 or (employee_catalog(own_company_id(),'','quiz')->>'total')::int <> 1 then raise exception 'Literal search/media filter incorrect'; end if;
 result := employee_lessons(own_company_id(),'c7000000-0000-4000-8000-000000000001');
 if result->'items'->0->>'module_title' <> 'First module' or result->'items'->1->>'module_title' <> 'Second module' then raise exception 'Lesson order reversed'; end if;
 begin perform save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000002',-1,false); raise exception 'Negative resume accepted'; exception when raise_exception then if sqlerrm <> 'Invalid progress' then raise; end if; end;
 begin perform save_employee_progress('b7000000-0000-4000-8000-000000000002','e7000000-0000-4000-8000-000000000002',10,false); raise exception 'Cross-company write accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
 begin perform save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000003',10,true); raise exception 'Unsupported quiz completion accepted'; exception when raise_exception then if sqlerrm <> 'Lesson unavailable' then raise; end if; end;
 perform save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000002',90,true);
 perform save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000002',15,false);
 if (select status from lesson_progress where lesson_id='e7000000-0000-4000-8000-000000000002') <> 'completed' then raise exception 'Resume downgraded completion'; end if;
 begin update lesson_progress set status='in_progress' where lesson_id='e7000000-0000-4000-8000-000000000002'; raise exception 'Direct downgrade accepted'; exception when insufficient_privilege then null; end;
 begin update lesson_progress set position_sec=-1 where lesson_id='e7000000-0000-4000-8000-000000000002'; raise exception 'Direct negative resume accepted'; exception when check_violation then null; end;
 if (employee_catalog(own_company_id(),'','video','in_progress')->>'total')::int <> 1 then raise exception 'Learning status filter incorrect'; end if;
 begin perform redeem_employee_reward('b7000000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001'); raise exception 'Stale company redemption accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
set local role service_role;
do $$ begin
 begin perform issue_employee_certificate('a7000000-0000-4000-8000-000000000001','ff700000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000001'); raise exception 'Incomplete certificate issued'; exception when raise_exception then if sqlerrm <> 'Course incomplete' then raise; end if; end;
 begin perform issue_employee_certificate('a7000000-0000-4000-8000-000000000001','ff700000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000003'); raise exception 'Empty course certified'; exception when raise_exception then if sqlerrm <> 'Course incomplete' then raise; end if; end;
end $$;
reset role;
set local role authenticated;
select save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000001',90,true);
select redeem_employee_reward(own_company_id(),'f7000000-0000-4000-8000-000000000001');
do $$ declare result jsonb; begin
 result := employee_summary(own_company_id());
 if (result->>'completed_course_count')::int <> 1 or (result->>'balance')::int <> 5 then raise exception 'Course completion/balance incorrect'; end if;
 if (select points from employee_ranking(own_company_id()) where user_id=auth.uid()) <> 5 then raise exception 'Ranking balance mismatch'; end if;
 begin perform redeem_employee_reward(own_company_id(),'f7000000-0000-4000-8000-000000000001'); raise exception 'Overspend accepted'; exception when raise_exception then if sqlerrm <> 'Insufficient points' then raise; end if; end;
end $$;
reset role;
set local role service_role;
do $$ declare first_id uuid; second_id uuid; begin
 first_id := issue_employee_certificate('a7000000-0000-4000-8000-000000000001','ff700000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000001');
 second_id := issue_employee_certificate('a7000000-0000-4000-8000-000000000001','ff700000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000001');
 if first_id<>second_id or (select code from certificates where id=first_id) !~ '^AUD-[0-9A-HJKMNP-TV-Z]{6}$' then raise exception 'Issuer not idempotent/code invalid'; end if;
end $$;
reset role;
update courses set status='paused' where id='c7000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 if (employee_certificates(own_company_id())->'items'->0->>'course_title') <> 'Video %_ course' or
   (employee_summary(own_company_id())->>'balance')::int <> 5 then raise exception 'Pause erased historical certificate/points'; end if;
 begin perform save_employee_progress(own_company_id(),'e7000000-0000-4000-8000-000000000001',90,true); raise exception 'Paused video write accepted'; exception when raise_exception then if sqlerrm <> 'Lesson unavailable' then raise; end if; end;
end $$;
select select_context('funcionario','b7000000-0000-4000-8000-000000000002');
do $$ begin
 if (employee_summary(own_company_id())->>'balance')::int <> 0 or (employee_certificates(own_company_id())->>'total')::int <> 0 then raise exception 'History crossed companies'; end if;
 begin perform employee_lessons(own_company_id(),'c7000000-0000-4000-8000-000000000002'); raise exception 'Private quiz leaked'; exception when raise_exception then if sqlerrm <> 'Course unavailable' then raise; end if; end;
end $$;
select select_context('empresa','b7000000-0000-4000-8000-000000000001');
do $$ begin
 begin perform employee_summary(own_company_id()); raise exception 'Manager learned'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
set local role service_role;
do $$ begin
 begin perform issue_employee_certificate('a7000000-0000-4000-8000-000000000001','ff700000-0000-4000-8000-000000000001','b7000000-0000-4000-8000-000000000001','c7000000-0000-4000-8000-000000000001'); raise exception 'Manager issued certificate'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
insert into courses(id,title) select md5('learning-page-'||n)::uuid,'Same title' from generate_series(1,52)n;
set local role authenticated;
select select_context('funcionario','b7000000-0000-4000-8000-000000000001');
do $$ declare first_page jsonb; last_page jsonb; begin
 first_page := employee_catalog(own_company_id(),'Same title');last_page := employee_catalog(own_company_id(),'Same title',null,null,50);
 if (first_page->>'total')::int<>52 or jsonb_array_length(first_page->'items')<>50 or jsonb_array_length(last_page->'items')<>2 or
   exists(select 1 from jsonb_array_elements(first_page->'items')a join jsonb_array_elements(last_page->'items')b on a->>'id'=b->>'id') then raise exception 'Pagination unstable'; end if;
end $$;
reset role;
delete from company_memberships where user_id='a7000000-0000-4000-8000-000000000001' and company_id='b7000000-0000-4000-8000-000000000001' and role='funcionario';
set local role authenticated;
do $$ begin
 begin perform employee_summary('b7000000-0000-4000-8000-000000000001'); raise exception 'Revoked context read data'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
 begin perform ranking('b7000000-0000-4000-8000-000000000001'); raise exception 'Revoked context saw ranking'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
rollback;
