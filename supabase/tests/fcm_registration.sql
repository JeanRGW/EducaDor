-- Isolated database only. Fixtures are rolled back.
begin;
insert into auth.users(id,email) values
 ('a9000000-0000-4000-8000-000000000001','push-a@example.test'),
 ('a9000000-0000-4000-8000-000000000002','push-b@example.test');
insert into public.profiles(id,full_name,email) values
 ('a9000000-0000-4000-8000-000000000001','A','push-a@example.test'),
 ('a9000000-0000-4000-8000-000000000002','B','push-b@example.test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001"}',true);
select public.set_push_enabled(false);
select public.register_fcm_token('test-token','android');
do $$ begin
 if (select push_enabled from public.notification_preferences) is distinct from false then raise exception 'Registration changed preference'; end if;
 begin
  insert into public.fcm_tokens(user_id, token) values (auth.uid(), 'bypass');
  raise exception 'Direct registration accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002"}',true);
select public.register_fcm_token('test-token','web');
select public.unregister_fcm_token('test-token');
select public.register_fcm_token('test-token','ios');
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001"}',true);
select public.unregister_fcm_token('test-token');
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
