-- Isolated fixtures, never run against a hosted project.
begin;
insert into auth.users(id,email) values
  ('a8900000-0000-4000-8000-000000000001','gender@example.test'),
  ('a8900000-0000-4000-8000-000000000002','other-gender@example.test');
insert into public.profiles(id,full_name,email) values
  ('a8900000-0000-4000-8000-000000000001','Gender','gender@example.test'),
  ('a8900000-0000-4000-8000-000000000002','Other','other-gender@example.test');
insert into public.platform_gestors(user_id) values ('a8900000-0000-4000-8000-000000000001');
insert into public.companies(id,name,code_prefix) values
  ('b8900000-0000-4000-8000-000000000001','Gender','GND'),
  ('b8900000-0000-4000-8000-000000000002','Other gender','GNO');
insert into public.company_memberships(user_id,company_id,role) values
  ('a8900000-0000-4000-8000-000000000001','b8900000-0000-4000-8000-000000000001','funcionario'),
  ('a8900000-0000-4000-8000-000000000001','b8900000-0000-4000-8000-000000000001','empresa');
insert into public.courses(id,title,all_companies) values ('c8900000-0000-4000-8000-000000000001','Gender',true);
insert into public.modules(id,course_id,title) values ('d8900000-0000-4000-8000-000000000001','c8900000-0000-4000-8000-000000000001','Module');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8900000-0000-4000-8000-000000000001","session_id":"ff890000-0000-4000-8000-000000000001","aal":"aal1"}',true);
select public.select_context('gestor',null);
do $$ declare m uuid:='d8900000-0000-4000-8000-000000000001'; l uuid; bad jsonb; saved jsonb; begin
  l:=public.save_content_lesson(m,'Both','video','{"video_id":"abcdefghijk","content_gender":"male","alternate_content":{"video_id":"ABCDEFGHIJK"},"points":17}');
  perform public.save_content_lesson(m,'Both','video','{"video_id":"abcdefghijk"}',l);
  if (select content_gender from public.lessons where id=l)<>'male' or (select alternate_content from public.lessons where id=l) is null then raise exception 'Legacy edit cleared variants'; end if;
  select to_jsonb(t) into saved from public.lessons t where id=l;
  for bad in select value from jsonb_array_elements('[
    {"video_id":"abcdefghijk","content_gender":"unknown"},
    {"video_id":"abcdefghijk","content_gender":null},
    {"video_id":"abcdefghijk","alternate_content":{"video_id":"bad"}},
    {"video_id":"abcdefghijk","alternate_content":{"video_id":"ABCDEFGHIJK","points":999}},
    {"video_id":"abcdefghijk","alternate_content":[]}
  ]') loop
    begin
      perform public.save_content_lesson(m,'Invalid','video',bad,l);
      raise exception 'Accepted invalid';
    exception when raise_exception then if sqlerrm='Accepted invalid' then raise; end if; end;
    if (select to_jsonb(t) from public.lessons t where id=l) is distinct from saved then raise exception 'Invalid save not atomic'; end if;
  end loop;
  perform public.save_content_lesson(m,'Single male','video','{"video_id":"abcdefghijk","content_gender":"male"}');
  perform public.save_content_lesson(m,'Single female','video','{"video_id":"ABCDEFGHIJK","content_gender":"female"}');
  perform public.save_content_lesson(m,'Neutral','video','{"video_id":"abcdefghijk"}');
  perform public.save_content_lesson(m,'Reading','reading','{"body":"primary","content_gender":"female","alternate_content":{"body":"alternate"}}');
  perform public.save_content_lesson(m,'Quiz','quiz','{"questions":[{"question":"Primary?","options":["Yes","No"],"answer":0}],"content_gender":"male","alternate_content":{"questions":[{"question":"Alternate?","options":["Yes","No"],"answer":1}]}}');
  perform public.save_content_lesson(m,'Animation','animation','{"file_key":"lessons/00000000-0000-4000-8000-000000000001.gif","content_gender":"male","alternate_content":{"image_keys":["lessons/00000000-0000-4000-8000-000000000002.png","lessons/00000000-0000-4000-8000-000000000003.webp"],"frame_ms":250}}');
  perform public.save_content_lesson(m,'Audio','audio','{"file_key":"lessons/00000000-0000-4000-8000-000000000001.mp3","content_gender":"male","alternate_content":{"file_key":"lessons/00000000-0000-4000-8000-000000000002.mp3"}}');
  perform public.save_content_lesson(m,'PDF','pdf','{"file_key":"lessons/00000000-0000-4000-8000-000000000001.pdf","content_gender":"male","alternate_content":{"file_key":"lessons/00000000-0000-4000-8000-000000000002.pdf"}}');
  for bad in select value from jsonb_array_elements('[
    {"image_keys":[null,"lessons/00000000-0000-4000-8000-000000000001.png"]},
    {"file_key":"https://example.test/private.gif"},
    {"image_keys":["lessons/00000000-0000-4000-8000-000000000001.png"]},
    {"file_key":"lessons/00000000-0000-4000-8000-000000000001.gif","frame_ms":99}
  ]'::jsonb) union all select jsonb_build_object('image_keys',to_jsonb(array_fill('lessons/00000000-0000-4000-8000-000000000001.png'::text,array[101]))) loop
    begin
      perform public.save_content_lesson(m,'Invalid animation','animation',jsonb_build_object(
        'file_key','lessons/00000000-0000-4000-8000-000000000001.gif','content_gender','male','alternate_content',bad));
      raise exception 'Invalid alternate animation accepted';
    exception when raise_exception then if sqlerrm='Invalid alternate animation accepted' then raise; end if; end;
  end loop;
end $$;
select public.select_context('funcionario','b8900000-0000-4000-8000-000000000001');
do $$ declare l uuid; row jsonb; g text; expected text; item jsonb; signature text; begin
  foreach signature in array array['public.employee_lesson_content(uuid)','public.update_own_profile(text,text,date,text,text)','public.save_employee_progress(uuid,uuid,integer,boolean,text)'] loop
    if has_function_privilege('anon',signature,'EXECUTE') or has_function_privilege('service_role',signature,'EXECUTE') or not has_function_privilege('authenticated',signature,'EXECUTE') then raise exception 'Bad RPC grant'; end if;
  end loop;
  if has_function_privilege('authenticated','public.resolved_lesson_content(public.lessons,text)','EXECUTE') or has_function_privilege('authenticated','public.validate_lesson_content(text,jsonb)','EXECUTE') then raise exception 'Private helper exposed'; end if;
  select id into l from public.lessons where title='Both';
  foreach g in array array[null::text,'male','female'] loop
    perform public.update_own_profile('Gender',null,null,null,g);
    row:=public.employee_lesson_content(l);
    expected:=case when g='female' then 'ABCDEFGHIJK' else 'abcdefghijk' end;
    if row->>'video_id' is distinct from expected or row ? 'alternate_content' or row->>'content_gender' is distinct from coalesce(g,'male') then raise exception 'Wrong effective video %',g; end if;
    select value into item from jsonb_array_elements(public.employee_lessons(public.own_company_id(),'c8900000-0000-4000-8000-000000000001')->'items') where value->>'id'=l::text;
    if item->>'video_id' is distinct from expected or item->>'content_gender' is distinct from row->>'content_gender' then raise exception 'List/content mismatch'; end if;
    for row in select public.employee_lesson_content(id) || jsonb_build_object('test_title',title) from public.lessons where title in ('Single male','Single female','Neutral') loop
      if row->>'video_id' is distinct from (case when row->>'test_title'='Single female' then 'ABCDEFGHIJK' else 'abcdefghijk' end) then raise exception 'Single fallback failed'; end if;
    end loop;
  end loop;
  perform public.update_own_profile('Legacy',null,null,null);
  if (select gender from public.profiles where id=auth.uid())<>'female' then raise exception 'Legacy profile cleared gender'; end if;
  begin perform public.update_own_profile('Invalid',null,null,null,'invalid'); raise exception 'Invalid profile accepted'; exception when raise_exception then if sqlerrm='Invalid profile accepted' then raise; end if; end;
  if (select full_name from public.profiles where id=auth.uid())<>'Legacy' then raise exception 'Invalid profile changed identity'; end if;
  row:=public.employee_lesson_content((select id from public.lessons where title='Quiz'));
  if row->'quiz_json'->0->>'question'<>'Alternate?' or row ? 'questions' then raise exception 'Quiz not normalized'; end if;
  row:=public.employee_lesson_content((select id from public.lessons where title='Animation'));
  if row->>'file_key' is not null or jsonb_array_length(row->'image_keys')<>2 or (row->>'frame_ms')::int<>250 then raise exception 'Alternate animation failed'; end if;
  row:=public.employee_lesson_content((select id from public.lessons where title='Audio'));
  if row->>'file_key' not like '%000000000002.mp3' then raise exception 'Alternate audio failed'; end if;
  row:=public.employee_lesson_content((select id from public.lessons where title='PDF'));
  if row->>'file_key' not like '%000000000002.pdf' then raise exception 'Alternate PDF failed'; end if;
  perform public.save_employee_progress(public.own_company_id(),l,31,true,'female');
  perform public.update_own_profile('Gender',null,null,null,'male');
  select value into item from jsonb_array_elements(public.employee_lessons(public.own_company_id(),'c8900000-0000-4000-8000-000000000001')->'items') where value->>'id'=l::text;
  if (item->>'position_sec')::int<>0 or item->>'status'<>'completed' then raise exception 'Variant resume/completion failed'; end if;
  perform public.save_employee_progress(public.own_company_id(),l,12,false,'male');
  select value into item from jsonb_array_elements(public.employee_lessons(public.own_company_id(),'c8900000-0000-4000-8000-000000000001')->'items') where value->>'id'=l::text;
  if (item->>'position_sec')::int<>12 or item->>'status'<>'completed' then raise exception 'Same variant resume failed'; end if;
  perform public.save_employee_progress(public.own_company_id(),l,45,false);
  if (select content_gender from public.lesson_progress where lesson_id=l) is not null then raise exception 'Legacy progress tag not unknown'; end if;
  if (select count(*) from public.lesson_progress where lesson_id=l)<>1 then raise exception 'Duplicate progress'; end if;
  if (public.employee_summary(public.own_company_id())->>'balance')::int<>17 then raise exception 'Variant change duplicated points'; end if;
  begin perform public.save_employee_progress(public.own_company_id(),(select id from public.lessons where title='Single male'),1,false,'female'); raise exception 'Unavailable variant accepted'; exception when raise_exception then if sqlerrm='Unavailable variant accepted' then raise; end if; end;
  begin perform public.save_employee_progress('b8900000-0000-4000-8000-000000000002',l,1,false,'male'); raise exception 'Cross-company progress'; exception when raise_exception then if sqlerrm='Cross-company progress' then raise; end if; end;
  perform public.update_own_profile('Gender',null,null,null,null);
  if (select gender from public.profiles where id=auth.uid()) is not null then raise exception 'Explicit clear failed'; end if;
end $$;
select public.select_context('empresa','b8900000-0000-4000-8000-000000000001');
do $$ begin
  begin perform public.employee_lesson_content('00000000-0000-4000-8000-000000000001'); raise exception 'Manager content bypass'; exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
end $$;
select public.select_context('gestor',null);
do $$ declare l uuid; begin
  select id into l from public.lessons where title='Both';
  perform public.save_content_lesson('d8900000-0000-4000-8000-000000000001','Both','video','{"video_id":"abcdefghijk","content_gender":null,"alternate_content":null}',l);
  if (select content_gender is not null or alternate_content is not null from public.lessons where id=l) then raise exception 'Explicit variant removal failed'; end if;
end $$;
-- Each release gate independently blocks the guarded content RPC.
do $$ declare l uuid; gate int; begin
  select id into l from public.lessons where title='Reading';
  for gate in 1..3 loop
    perform public.select_context('gestor',null);
    if gate=1 then perform public.set_course_platform_enabled('c8900000-0000-4000-8000-000000000001',false);
    elsif gate=2 then perform public.set_course_audience('c8900000-0000-4000-8000-000000000001',false,array['b8900000-0000-4000-8000-000000000002'::uuid]);
    else
      perform public.select_context('empresa','b8900000-0000-4000-8000-000000000001');
      perform public.set_course_company_enabled('c8900000-0000-4000-8000-000000000001',false);
    end if;
    perform public.select_context('funcionario','b8900000-0000-4000-8000-000000000001');
    begin perform public.employee_lesson_content(l); raise exception 'Course gate bypass'; exception when raise_exception then if sqlerrm<>'Lesson unavailable' then raise; end if; end;
    perform public.select_context('gestor',null);
    if gate=1 then perform public.set_course_platform_enabled('c8900000-0000-4000-8000-000000000001',true);
    elsif gate=2 then perform public.set_course_audience('c8900000-0000-4000-8000-000000000001',true,'{}'::uuid[]);
    end if;
  end loop;
end $$;
reset role;
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values ('a8900000-0000-4000-8000-000000000003','a8900000-0000-4000-8000-000000000001','totp','verified',now(),now());
set local role authenticated;
do $$ begin
  begin perform public.update_own_profile('Bypass',null,null,null,'female'); raise exception 'MFA profile bypass'; exception when insufficient_privilege then null; end;
  begin perform public.employee_lesson_content('00000000-0000-4000-8000-000000000001'); raise exception 'MFA content bypass'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  if (select gender from public.profiles where id='a8900000-0000-4000-8000-000000000002') is not null then raise exception 'Other profile changed'; end if;
end $$;
rollback;
