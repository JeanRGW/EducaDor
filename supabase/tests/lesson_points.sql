-- Isolated local database only; fixtures and mutations roll back.
begin;
insert into auth.users(id,email) values ('a8400000-0000-4000-8000-000000000001','points@example.test');
insert into public.profiles(id,full_name,email) values ('a8400000-0000-4000-8000-000000000001','Points','points@example.test');
insert into public.platform_gestors(user_id) values ('a8400000-0000-4000-8000-000000000001');
insert into public.companies(id,name,code_prefix) values ('b8400000-0000-4000-8000-000000000001','Points','PTS');
insert into public.company_memberships(user_id,company_id,role) values
  ('a8400000-0000-4000-8000-000000000001','b8400000-0000-4000-8000-000000000001','funcionario');
insert into public.courses(id,title,all_companies) values ('c8400000-0000-4000-8000-000000000001','Points',true);
insert into public.modules(id,course_id,title) values ('d8400000-0000-4000-8000-000000000001','c8400000-0000-4000-8000-000000000001','Module');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8400000-0000-4000-8000-000000000001","session_id":"ff840000-0000-4000-8000-000000000001"}',true);
select public.select_context('gestor',null);
do $$
declare
  m uuid := 'd8400000-0000-4000-8000-000000000001';
  l uuid; created uuid; n int; bad jsonb;
begin
  l := public.save_content_lesson(m,'Legacy','reading','{"body":"Read"}');
  if (select points from public.lessons where id=l) <> 10 then raise exception 'Default changed'; end if;
  foreach n in array array[0,-5,37,2147483647,-2147483648] loop
    created := public.save_content_lesson(m,'Explicit','reading',jsonb_build_object('body','Read','points',n));
    if (select points from public.lessons where id=created) <> n then raise exception 'Create lost points'; end if;
    if public.save_content_lesson(m,'Edited','reading',jsonb_build_object('body','Updated','points',n),l) <> l then raise exception 'ID changed'; end if;
    perform public.save_content_lesson(m,'Legacy edit','reading','{"body":"Updated again"}',l);
    if (select points from public.lessons where id=l) <> n then raise exception 'Omission reset points'; end if;
  end loop;
  for bad in select value from jsonb_array_elements('[1.5,"1.5","abc",null,2147483648,-2147483649,true,{},[]]'::jsonb) loop
    begin
      perform public.save_content_lesson(m,'Invalid','reading',jsonb_build_object('body','Read','points',bad),l);
      raise exception 'Invalid points accepted: %',bad;
    exception when invalid_text_representation or numeric_value_out_of_range or not_null_violation then null;
    end;
    begin
      perform public.save_content_lesson(m,'Invalid create','reading',jsonb_build_object('body','Read','points',bad));
      raise exception 'Invalid create points accepted: %',bad;
    exception when invalid_text_representation or numeric_value_out_of_range or not_null_violation then null;
    end;
  end loop;
  if (select count(*) from public.lessons where module_id=m) <> 6 then raise exception 'Invalid create leaked a lesson'; end if;
  perform public.select_context('funcionario','b8400000-0000-4000-8000-000000000001');
  perform public.save_employee_progress('b8400000-0000-4000-8000-000000000001',l,23,true);
  perform public.select_context('gestor',null);
  perform public.save_content_lesson(m,'Points edited','reading','{"body":"Updated","points":25}',l);
  if not exists(select 1 from public.lessons where id=l and position=1 and points=25) then raise exception 'Identity or position changed'; end if;
  if not exists(select 1 from public.lesson_progress where lesson_id=l and status='completed' and position_sec=23) then raise exception 'Progress reset'; end if;
end $$;
rollback;
