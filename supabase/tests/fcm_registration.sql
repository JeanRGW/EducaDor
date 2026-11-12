-- Isolated database only. Fixtures are rolled back.
begin;
insert into auth.users(id,email) values
 ('a9000000-0000-4000-8000-000000000001','push-a@example.test'),
 ('a9000000-0000-4000-8000-000000000002','push-b@example.test');
insert into public.profiles(id,full_name,email) values
 ('a9000000-0000-4000-8000-000000000001','A','push-a@example.test'),
 ('a9000000-0000-4000-8000-000000000002','B','push-b@example.test');
insert into companies(id,name) values ('b9000000-0000-4000-8000-000000000001','Company');
insert into company_memberships(user_id,company_id,role) values
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','funcionario'),
 ('a9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','funcionario');
-- Auth session rows: the application guard rejects tokens without a live session.
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('f9000000-0000-4000-8000-000000000001','a9000000-0000-4000-8000-000000000001',now(),now(),now()+interval '24 hours'),
 ('f9000000-0000-4000-8000-000000000002','a9000000-0000-4000-8000-000000000002',now(),now(),now()+interval '24 hours')
 on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"f9000000-0000-4000-8000-000000000001"}',true);
select public.select_context('funcionario','b9000000-0000-4000-8000-000000000001');
select public.set_push_enabled(false);
select public.register_fcm_token('test-token','android');
do $$ begin
 if (select push_enabled from public.notification_preferences) is distinct from false then raise exception 'Registration changed preference'; end if;
 begin
  insert into public.fcm_tokens(user_id, token) values (auth.uid(), 'bypass');
  raise exception 'Direct registration accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002","session_id":"f9000000-0000-4000-8000-000000000002"}',true);
do $$ begin
 begin perform public.register_fcm_token('test-token','web'); raise exception 'Missing context accepted';
 exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
do $$ begin if (select user_id from fcm_tokens where token='test-token') <> 'a9000000-0000-4000-8000-000000000001' then raise exception 'Missing context transferred token'; end if; end $$;
set local role authenticated;
select public.select_context('funcionario','b9000000-0000-4000-8000-000000000001');
reset role;
update companies set active = false where id='b9000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin
 begin perform public.register_fcm_token('test-token','web'); raise exception 'Inactive context accepted';
 exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
do $$ begin if (select user_id from fcm_tokens where token='test-token') <> 'a9000000-0000-4000-8000-000000000001' then raise exception 'Inactive context transferred token'; end if; end $$;
update companies set active = true where id='b9000000-0000-4000-8000-000000000001';
delete from company_memberships where user_id='a9000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
 begin perform public.register_fcm_token('test-token','web'); raise exception 'Revoked context accepted';
 exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
do $$ begin if (select user_id from fcm_tokens where token='test-token') <> 'a9000000-0000-4000-8000-000000000001' then raise exception 'Revoked context transferred token'; end if; end $$;
insert into company_memberships(user_id,company_id,role) values ('a9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','funcionario');
set local role authenticated;
select public.register_fcm_token('test-token','web');
select public.unregister_fcm_token('test-token');
select public.register_fcm_token('test-token','ios');
reset role;
do $$ declare old_updated timestamptz; old_owner uuid; begin
 select user_id,updated_at into old_owner,old_updated from fcm_tokens where token='test-token';
 update fcm_tokens set updated_at = old_updated + interval '1 second' where token='test-token';
 delete from fcm_tokens where user_id=old_owner and token='test-token' and updated_at=old_updated;
 if not exists(select 1 from fcm_tokens where token='test-token') then raise exception 'Refresh lost to stale cleanup'; end if;
 update fcm_tokens set user_id='a9000000-0000-4000-8000-000000000001' where token='test-token';
 delete from fcm_tokens where user_id=old_owner and token='test-token' and updated_at=old_updated;
 if not exists(select 1 from fcm_tokens where token='test-token' and user_id='a9000000-0000-4000-8000-000000000001') then raise exception 'Transfer lost to stale cleanup'; end if;
 update fcm_tokens set user_id=old_owner where token='test-token';
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001"}',true);
do $$ begin
  begin perform public.unregister_fcm_token('test-token');
    raise exception 'Sessionless unregister accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.fcm_tokens where token='test-token') <> 1 or
    (select user_id from public.fcm_tokens where token='test-token') <> 'a9000000-0000-4000-8000-000000000002' then
   raise exception 'Token transfer or owner-scoped unregister failed';
 end if;
 if (select push_enabled from public.notification_preferences where user_id='a9000000-0000-4000-8000-000000000001') is distinct from false then
   raise exception 'Preference lost';
 end if;
end $$;
rollback;
