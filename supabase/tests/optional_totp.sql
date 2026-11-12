begin;
insert into auth.users(id,email) values ('a8000000-0000-4000-8000-000000000001','mfa@example.test');
insert into public.profiles(id,full_name,email) values ('a8000000-0000-4000-8000-000000000001','MFA','mfa@example.test');
insert into public.platform_gestors(user_id) values ('a8000000-0000-4000-8000-000000000001');
insert into public.companies(id,name) values ('b8000000-0000-4000-8000-000000000001','MFA company');
insert into public.company_memberships(user_id,company_id,role) values
  ('a8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','empresa'),
  ('a8000000-0000-4000-8000-000000000001','b8000000-0000-4000-8000-000000000001','funcionario');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values ('a8000000-0000-4000-8000-000000000002','a8000000-0000-4000-8000-000000000001','totp','unverified',now(),now());
-- Auth session rows: the application guard rejects tokens without a live session.
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('a8000000-0000-4000-8000-000000000003','a8000000-0000-4000-8000-000000000001',now(),now(),now()+interval '24 hours')
 on conflict do nothing;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"a8000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
select public.select_context('gestor',null);
select public.clear_context();
do $$ begin if public.context_role() is not null then raise exception 'Unverified enrollment clear failed'; end if; end $$;
select public.select_context('gestor',null);
select public.update_own_profile('Before',null,null,null);
select public.set_push_enabled(false);
select public.register_fcm_token('mfa-test-token','web');
reset role;
update auth.mfa_factors set status='verified';
set local role authenticated;
do $$ begin
  begin perform public.context_role(); raise exception 'AAL1 context bypass'; exception when insufficient_privilege then null; end;
  begin perform public.available_contexts(); raise exception 'AAL1 contexts bypass'; exception when insufficient_privilege then null; end;
  begin perform public.select_context('gestor',null); raise exception 'AAL1 selection bypass'; exception when insufficient_privilege then null; end;
  begin perform public.clear_context(); raise exception 'AAL1 clear bypass'; exception when insufficient_privilege then null; end;
  begin perform public.update_own_profile('Bypass',null,null,null); raise exception 'AAL1 profile bypass'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.profiles; raise exception 'AAL1 profile read bypass'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.notification_preferences; raise exception 'AAL1 preference read bypass'; exception when insufficient_privilege then null; end;
  begin perform public.register_fcm_token('mfa-test-token','android'); raise exception 'AAL1 token registration bypass'; exception when insufficient_privilege then null; end;
  begin perform public.set_push_enabled(true); raise exception 'AAL1 preference write bypass'; exception when insufficient_privilege then null; end;
  begin perform public.unregister_fcm_token('mfa-test-token'); raise exception 'AAL1 unregister bypass'; exception when insufficient_privilege then null; end;
  if has_table_privilege('authenticated','auth.mfa_factors','select') then raise exception 'Auth factor table exposed'; end if;
end $$;
reset role;
do $$ begin
  if not exists (select 1 from public.session_contexts where session_id='a8000000-0000-4000-8000-000000000003' and role='gestor') then
    raise exception 'AAL1 clear removed context';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"a8000000-0000-4000-8000-000000000003","aal":"aal2"}',true);
select public.require_mfa_if_enrolled();
select public.select_context('gestor',null);
select public.update_own_profile('After',null,null,null);
do $$ begin
  if public.context_role() <> 'gestor' then raise exception 'AAL2 role unavailable'; end if;
  if (select push_enabled from public.notification_preferences) is distinct from false then raise exception 'AAL2 preference unavailable'; end if;
end $$;
select public.register_fcm_token('mfa-test-token','android');
select public.set_push_enabled(true);
select public.clear_context();
select public.unregister_fcm_token('mfa-test-token');
reset role;
do $$ begin if exists (select 1 from public.fcm_tokens where token='mfa-test-token') then raise exception 'AAL2 cleanup without context failed'; end if; end $$;
set local role authenticated;
do $$ begin if public.context_role() is not null then raise exception 'AAL2 clear failed'; end if; end $$;
-- Verify the guard before deletion for each company role too.
do $$ declare r text; begin
  foreach r in array array['empresa','funcionario'] loop
    perform public.select_context(r,'b8000000-0000-4000-8000-000000000001');
    perform set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"a8000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
    begin perform public.clear_context(); raise exception 'AAL1 clear bypass for %', r; exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"a8000000-0000-4000-8000-000000000003","aal":"aal2"}',true);
    if public.context_role() is distinct from r then raise exception 'AAL1 clear removed % context', r; end if;
    perform public.clear_context();
    if public.context_role() is not null then raise exception 'AAL2 clear failed for %', r; end if;
  end loop;
end $$;
-- No verified or unverified factor: ordinary AAL1 sessions can clear.
reset role;
delete from auth.mfa_factors where user_id='a8000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"a8000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
select public.select_context('gestor',null);
select public.clear_context();
do $$ begin if public.context_role() is not null then raise exception 'Unenrolled clear failed'; end if; end $$;
rollback;
