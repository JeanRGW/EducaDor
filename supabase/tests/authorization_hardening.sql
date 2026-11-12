-- Isolated local regression; no persistent Auth or object writes.
begin;
insert into auth.users(id,email) values
 ('a9000000-0000-4000-8000-000000000001','security@example.test'),
 ('a9000000-0000-4000-8000-000000000002','other@example.test');
insert into profiles(id,full_name,email,needs_password) values
 ('a9000000-0000-4000-8000-000000000001','Security','security@example.test',true),
 ('a9000000-0000-4000-8000-000000000002','Other','other@example.test',true);
insert into companies(id,name) values ('b9000000-0000-4000-8000-000000000001','Security');
insert into company_memberships(user_id,company_id,role) values
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','funcionario'),
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','empresa');
insert into platform_gestors(user_id) values ('a9000000-0000-4000-8000-000000000001');
insert into courses(id,title) values ('c9000000-0000-4000-8000-000000000001','Security');
insert into modules(id,course_id,title) values ('d9000000-0000-4000-8000-000000000001','c9000000-0000-4000-8000-000000000001','Module');
insert into lessons(id,module_id,title,kind,video_id) values ('e9000000-0000-4000-8000-000000000001','d9000000-0000-4000-8000-000000000001','Video','video','abcdefghijk');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"f9000000-0000-4000-8000-000000000001"}',true);
do $$ declare field text; begin
 foreach field in array array['full_name','phone','address','birth_date','avatar_key','needs_password','email'] loop
   if has_column_privilege('authenticated','profiles',field,'UPDATE') then raise exception 'Direct profile column writable: %',field; end if;
 end loop;
 begin update profiles set needs_password=false; raise exception 'Flag forged'; exception when insufficient_privilege then null; end;
 begin update profiles set full_name=''; raise exception 'Validation bypass'; exception when insufficient_privilege then null; end;
 begin perform complete_password_setup(); raise exception 'Missing password accepted'; exception when raise_exception then if sqlerrm <> 'Password unavailable' then raise; end if; end;
 perform update_own_profile(' Edited ',' 123 ',null,' Address ');
 if not exists(select 1 from public.own_profile() where id=auth.uid() and full_name='Edited' and phone='123' and address='Address' and needs_password) then raise exception 'Own RPC failed'; end if;
 begin perform update_own_profile('',null,null,null); raise exception 'Invalid profile accepted'; exception when raise_exception then if sqlerrm <> 'Invalid profile' then raise; end if; end;
end $$;
-- Empty string is also Auth's no-password representation.
reset role;
update auth.users set encrypted_password='' where id='a9000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform complete_password_setup(); raise exception 'Empty password accepted'; exception when raise_exception then if sqlerrm <> 'Password unavailable' then raise; end if; end;
 if has_table_privilege('authenticated','certificates','INSERT,UPDATE,DELETE') or
    has_table_privilege('authenticated','redemptions','INSERT,UPDATE,DELETE') then raise exception 'Unnecessary write grants retained'; end if;
end $$;
-- Privileged fixture models Auth storing a password, never application Auth DML.
reset role;
update auth.users set encrypted_password=extensions.crypt('local-fixture-password',extensions.gen_salt('bf')) where id='a9000000-0000-4000-8000-000000000001';
set local role authenticated;
select complete_password_setup();
select complete_password_setup();
do $$ begin
 if (select needs_password from profiles where id=auth.uid()) then raise exception 'Completion did not clear own flag'; end if;
end $$;
reset role;
do $$ begin
 if not (select needs_password from profiles where id='a9000000-0000-4000-8000-000000000002') or
   (select full_name from profiles where id='a9000000-0000-4000-8000-000000000002') <> 'Other' then raise exception 'Own RPC changed another identity'; end if;
end $$;
set local role authenticated;
select select_context('funcionario','b9000000-0000-4000-8000-000000000001');
select save_employee_progress(own_company_id(),'e9000000-0000-4000-8000-000000000001',20,true);
do $$ begin
 begin
 insert into lesson_progress(user_id,company_id,lesson_id,updated_at) values(auth.uid(),own_company_id(),'e9000000-0000-4000-8000-000000000001','2099-01-01');
 raise exception 'Forged insert timestamp accepted'; exception when insufficient_privilege then null; end;
 begin update lesson_progress set updated_at='2000-01-01',score=100; raise exception 'Forged update accepted'; exception when insufficient_privilege then null; end;
 if not exists(select 1 from lesson_progress where user_id=auth.uid() and status='completed' and updated_at=now() and score is null) then raise exception 'RPC timestamp invalid'; end if;
 begin perform save_employee_progress('b9000000-0000-4000-8000-000000000002','e9000000-0000-4000-8000-000000000001',0,true); raise exception 'Crosscompany accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
select select_context('empresa','b9000000-0000-4000-8000-000000000001');
do $$ begin
 begin perform save_employee_progress(own_company_id(),'e9000000-0000-4000-8000-000000000001',0,true); raise exception 'Manager learned'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
 begin insert into storage.objects(bucket_id,name) values ('educador-public','covers/manager.webp'); raise exception 'Manager uploaded public cover'; exception when insufficient_privilege then null; end;
end $$;
select select_context('gestor',null);
insert into storage.objects(bucket_id,name) values ('educador-public','covers/security_test.webp');
do $$ declare key text; begin
 foreach key in array array['avatars/security.webp','lessons/security.webp','covers/../escape.webp','covers/file.png','covers/nested/file.webp'] loop
 begin insert into storage.objects(bucket_id,name) values ('educador-public',key); raise exception 'Invalid public key accepted: %',key; exception when insufficient_privilege then null; end;
 end loop;
 begin update storage.objects set name='avatars/renamed.webp' where name='covers/security_test.webp'; raise exception 'Invalid rename accepted'; exception when insufficient_privilege then null; end;
end $$;
update storage.objects set name='covers/renamed.webp' where name='covers/security_test.webp';
set local role anon;
do $$ begin
 if not exists(select 1 from storage.objects where name='covers/renamed.webp') then raise exception 'Public read broken'; end if;
 if has_function_privilege('anon','complete_password_setup()','EXECUTE') then raise exception 'Anonymous completion allowed'; end if;
end $$;
reset role;
rollback;
