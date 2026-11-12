-- Run on an isolated database after migrations. All fixtures roll back.
begin;
insert into auth.users(id,email) values ('a8300000-0000-4000-8000-000000000001','formats@example.test');
insert into public.profiles(id,full_name,email) values ('a8300000-0000-4000-8000-000000000001','Formats','formats@example.test');
insert into public.companies(id,name,code_prefix) values ('b8300000-0000-4000-8000-000000000001','Formats','FMT');
insert into public.platform_gestors(user_id) values ('a8300000-0000-4000-8000-000000000001');
insert into public.company_memberships(user_id,company_id,role) values
  ('a8300000-0000-4000-8000-000000000001','b8300000-0000-4000-8000-000000000001','funcionario'),
  ('a8300000-0000-4000-8000-000000000001','b8300000-0000-4000-8000-000000000001','empresa');
insert into public.courses(id,title,all_companies) values ('c8300000-0000-4000-8000-000000000001','Formats',true);
insert into public.modules(id,course_id,title) values ('d8300000-0000-4000-8000-000000000001','c8300000-0000-4000-8000-000000000001','Module');
-- Auth session rows: the application guard rejects tokens without a live session.
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('ff830000-0000-4000-8000-000000000001','a8300000-0000-4000-8000-000000000001',now(),now(),now()+interval '24 hours')
 on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8300000-0000-4000-8000-000000000001","session_id":"ff830000-0000-4000-8000-000000000001"}',true);
select public.select_context('gestor',null);
do $$ declare c uuid; m uuid; l uuid; kind text; signature text; begin
  foreach signature in array array['public.create_content_course(text)','public.save_content_module(uuid,text,uuid)','public.save_content_lesson(uuid,text,text,jsonb,uuid)'] loop
    if has_function_privilege('anon',signature,'EXECUTE') or not has_function_privilege('authenticated',signature,'EXECUTE') then raise exception 'Incorrect grants'; end if;
  end loop;
  c := public.create_content_course('New course');
  if (select status from public.courses where id=c)<>'paused' then raise exception 'New course was released'; end if;
  m := public.save_content_module(c,'First');
  perform public.save_content_module(c,'Renamed',m);
  if (select title from public.modules where id=m)<>'Renamed' then raise exception 'Rename failed'; end if;
  l:=public.save_content_module(c,'Second');
  perform public.move_content_item('module',l,-1);
  if (select id from public.modules where course_id=c order by position,id limit 1)<>l then raise exception 'Module reorder failed'; end if;
  perform public.move_content_item('module',l,-1);
  m := 'd8300000-0000-4000-8000-000000000001';
  perform public.save_content_lesson(m,'Video','video','{"video_id":"abcdefghijk","body":"Supporting text"}');
  perform public.save_content_lesson(m,'Audio','audio','{"file_key":"lessons/00000000-0000-4000-8000-000000000001.mp3"}');
  select id into l from public.lessons where module_id=m and title='Audio';
  perform public.move_content_item('lesson',l,-1);
  if (select title from public.lessons where module_id=m order by position,id limit 1)<>'Audio' then raise exception 'Lesson reorder failed'; end if;
  perform public.move_content_item('lesson',l,1);
  perform public.save_content_lesson(m,'PDF','pdf','{"file_key":"lessons/00000000-0000-4000-8000-000000000002.pdf"}');
  l := public.save_content_lesson(m,'Reading','reading','{"body":"Read this"}');
  perform public.save_content_lesson(m,'Reading edited','reading','{"body":"Updated text"}',l);
  perform public.save_content_lesson(m,'Quiz','quiz','{"questions":[{"question":"Question?","options":["Yes","No"],"answer":0}]}');
  perform public.save_content_lesson(m,'GIF','animation','{"file_key":"lessons/00000000-0000-4000-8000-000000000003.gif"}');
  perform public.save_content_lesson(m,'Sequence','animation','{"image_keys":["lessons/00000000-0000-4000-8000-000000000004.png","lessons/00000000-0000-4000-8000-000000000005.webp"],"frame_ms":500}');
  foreach kind in array array['video','audio','pdf','quiz','reading','animation'] loop
    begin perform public.save_content_lesson(m,'Invalid',kind,'{}'); raise exception 'Empty format accepted';
      exception when raise_exception then if sqlerrm='Empty format accepted' then raise; end if; end;
  end loop;
  begin perform public.save_content_lesson(m,'Bad key','animation','{"file_key":"https://example.com/a.gif"}'); raise exception 'External URL accepted';
    exception when raise_exception then if sqlerrm<>'Invalid file' then raise; end if; end;
  if (select count(*) from public.lessons where module_id=m)<>7 then raise exception 'Hierarchy lost lessons'; end if;
  if (select l.body from public.lessons l where l.module_id=m and l.kind='video')<>'Supporting text' then raise exception 'Media lost supporting text'; end if;
  if (select module_count from public.content_catalog() where id='c8300000-0000-4000-8000-000000000001')<>1 or
    (select lesson_count from public.content_catalog() where id='c8300000-0000-4000-8000-000000000001')<>7 then raise exception 'Incorrect catalog counts'; end if;
end $$;
select public.select_context('empresa','b8300000-0000-4000-8000-000000000001');
do $$ begin
  if exists(select 1 from public.lessons where module_id='d8300000-0000-4000-8000-000000000001') then raise exception 'Manager read lesson files'; end if;
  begin perform public.delete_content('course','c8300000-0000-4000-8000-000000000001'); raise exception 'Manager deleted course';
    exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
  begin perform public.move_content_item('module','d8300000-0000-4000-8000-000000000001',1); raise exception 'Manager reordered content';
    exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
  if (select module_count from public.content_catalog() where id='c8300000-0000-4000-8000-000000000001')<>1 then raise exception 'Manager missing module count'; end if;
  begin perform public.create_content_course('Forbidden'); raise exception 'Manager created course';
    exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
end $$;
select public.select_context('funcionario','b8300000-0000-4000-8000-000000000001');
do $$ declare l uuid; begin
  begin perform public.delete_content('module','d8300000-0000-4000-8000-000000000001'); raise exception 'Employee deleted module';
    exception when raise_exception then if sqlerrm<>'Forbidden' then raise; end if; end;
  for l in select id from public.lessons where module_id='d8300000-0000-4000-8000-000000000001' loop
    perform public.save_employee_progress(public.own_company_id(),l,0,true);
    perform public.save_employee_progress(public.own_company_id(),l,0,false);
  end loop;
  if (select count(*) from public.lesson_progress where status='completed')<>7 then raise exception 'Completion lost'; end if;
end $$;
select public.select_context('gestor',null);
select public.set_course_platform_enabled('c8300000-0000-4000-8000-000000000001',false);
select public.select_context('funcionario','b8300000-0000-4000-8000-000000000001');
do $$ begin
  if exists(select 1 from public.lessons where module_id='d8300000-0000-4000-8000-000000000001') then raise exception 'Paused file metadata leaked'; end if;
end $$;
select public.select_context('gestor',null);
select public.set_course_platform_enabled('c8300000-0000-4000-8000-000000000001',true);
do $$ declare ext text; l uuid; begin
  foreach ext in array array['png','jpg','webp'] loop
    l:=public.save_content_lesson('d8300000-0000-4000-8000-000000000001','Still '||ext,'animation',
      jsonb_build_object('file_key','lessons/00000000-0000-4000-8000-000000000006.'||ext,'body','Image caption'));
    if (select body from public.lessons where id=l)<>'Image caption' then raise exception 'Still image lost text'; end if;
  end loop;
  begin perform public.save_content_lesson('d8300000-0000-4000-8000-000000000001','Invalid image','animation',
    '{"file_key":"lessons/00000000-0000-4000-8000-000000000006.pdf"}'); raise exception 'PDF accepted as image';
    exception when raise_exception then if sqlerrm<>'Missing content' then raise; end if; end;
end $$;
select public.select_context('funcionario','b8300000-0000-4000-8000-000000000001');
do $$ declare l uuid; begin
  for l in select id from public.lessons where title like 'Still %' loop
    perform public.save_employee_progress(public.own_company_id(),l,0,true);
  end loop;
  if (select count(*) from public.lesson_progress where status='completed')<>10 then raise exception 'Still image completion missing'; end if;
end $$;
select public.select_context('gestor',null);
do $$ declare l uuid; begin
  select id into l from public.lessons where title='Still webp';
  perform public.move_content_item('lesson',l,-1);
  if (select count(*) from public.lesson_progress where status='completed')<>10 then raise exception 'Reorder reset progress'; end if;
  begin perform public.move_content_item('lesson',l,0); raise exception 'Invalid direction accepted';
    exception when raise_exception then if sqlerrm<>'Invalid move' then raise; end if; end;
end $$;
do $$ declare l uuid; m uuid:='d8300000-0000-4000-8000-000000000001'; c uuid:='c8300000-0000-4000-8000-000000000001'; begin
  if has_function_privilege('anon','public.delete_content(text,uuid)','EXECUTE') then raise exception 'Anonymous delete grant'; end if;
  l:=public.save_content_module(c,'Appended module');
  if (select id from public.modules where course_id=c order by position desc,id desc limit 1)<>l then raise exception 'New module not appended'; end if;
  perform public.delete_content('module',l);
  l:=public.save_content_lesson(m,'Appended lesson','reading','{"body":"Last"}');
  if (select id from public.lessons where module_id=m order by position desc,id desc limit 1)<>l then raise exception 'New lesson not appended'; end if;
  perform public.delete_content('lesson',l);
  select id into l from public.lessons where title='Still png';
  perform public.delete_content('lesson',l);
  if exists(select 1 from public.lessons where id=l) or exists(select 1 from public.lesson_progress where lesson_id=l) then raise exception 'Lesson deletion failed'; end if;
  if not exists(select 1 from public.lessons where title='Still jpg') then raise exception 'Sibling deleted'; end if;
  perform public.delete_content('module',m);
  if exists(select 1 from public.modules where id=m) or exists(select 1 from public.lessons where module_id=m) then raise exception 'Module deletion failed'; end if;
  if not exists(select 1 from public.courses where id=c) then raise exception 'Module deleted parent course'; end if;
  perform public.delete_content('course',c);
  if exists(select 1 from public.courses where id=c) then raise exception 'Course deletion failed'; end if;
end $$;
rollback;
