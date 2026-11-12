-- Isolated local regression for session revocation. Fixtures roll back.
-- A password reset or factor removal deletes Auth sessions while an unexpired
-- access token can remain; this guard must deny that token everywhere.
begin;
insert into auth.users(id,email) values
 ('a6000000-0000-4000-8000-000000000001','revoked-gestor@example.test'),
 ('a6000000-0000-4000-8000-000000000002','revoked-employee@example.test');
insert into profiles(id,full_name,email) values
 ('a6000000-0000-4000-8000-000000000001','Gestor','revoked-gestor@example.test'),
 ('a6000000-0000-4000-8000-000000000002','Employee','revoked-employee@example.test');
insert into platform_gestors(user_id) values ('a6000000-0000-4000-8000-000000000001');
insert into companies(id,name) values ('b6000000-0000-4000-8000-000000000001','Revocation');
insert into company_memberships(user_id,company_id,role) values
 ('a6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','funcionario');
insert into courses(id,title,status) values ('c6000000-0000-4000-8000-000000000001','Revoked course','released');
insert into modules(id,course_id,title) values ('d6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001','Module');
insert into lessons(id,module_id,title,kind,file_key) values ('e6000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','PDF','pdf','lessons/00000000-0000-4000-8000-000000000001.pdf');
insert into lesson_progress(user_id,company_id,lesson_id,status) values ('a6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000001','completed');
insert into notification_preferences(user_id,push_enabled) values ('a6000000-0000-4000-8000-000000000002',false);
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('f6000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
 ('f6000000-0000-4000-8000-000000000002','a6000000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour'),
 ('f6000000-0000-4000-8000-000000000003','a6000000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour'),
 ('f6000000-0000-4000-8000-000000000004','a6000000-0000-4000-8000-000000000002',now(),now(),now()-interval '1 minute'),
 ('f6000000-0000-4000-8000-000000000005','a6000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values
 ('a6000000-0000-4000-8000-000000000003','a6000000-0000-4000-8000-000000000001','totp','verified',now(),now());
insert into storage.objects(bucket_id,name) values ('educador-public','covers/existing.webp');

-- The new helper and Auth's session store are not client-accessible.
do $$ begin
  if has_table_privilege('authenticated','auth.sessions','SELECT') then
    raise exception 'Auth session table exposed'; end if;
  if has_function_privilege('authenticated','public.require_live_session_id(uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','public.require_live_session_id(uuid,uuid)','EXECUTE') then
    raise exception 'Service-only session check exposed'; end if;
end $$;

-- Live session: MFA is still the second independent gate.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'AAL1 live session bypassed MFA'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.profiles; raise exception 'AAL1 live session read profiles'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
select public.select_context('gestor',null);
do $$ begin
  if public.context_role() <> 'gestor' then raise exception 'Live session lost its context'; end if;
  if (select count(*) from public.profiles) <> 2 then raise exception 'Live session lost direct reads'; end if;
end $$;
reset role;
delete from auth.mfa_factors where user_id='a6000000-0000-4000-8000-000000000001';
update auth.sessions set not_after=now()-interval '1 minute' where id='f6000000-0000-4000-8000-000000000005';

-- Expired Auth session (not_after) is treated like revocation.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000005","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'Expired session accepted'; exception when insufficient_privilege then null; end;
end $$;

-- Revoked session: direct RLS, context helpers, writes, storage and reselect fail.
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000002","session_id":"f6000000-0000-4000-8000-000000000002","aal":"aal1"}',true);
select public.select_context('funcionario','b6000000-0000-4000-8000-000000000001');
do $$ begin
  if public.context_role() <> 'funcionario' or (select count(*) from public.courses) <> 1 then
    raise exception 'Live employee access unavailable';
  end if;
end $$;
reset role;
delete from auth.sessions where id='f6000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin
  begin perform public.context_role(); raise exception 'Revoked context accepted'; exception when insufficient_privilege then null; end;
  begin perform public.selected_context(); raise exception 'Revoked selected context accepted'; exception when insufficient_privilege then null; end;
  begin perform public.select_context('funcionario','b6000000-0000-4000-8000-000000000001'); raise exception 'Revoked reselect accepted'; exception when insufficient_privilege then null; end;
  begin perform public.update_own_profile('Revoked',null,null,null); raise exception 'Revoked profile write accepted'; exception when insufficient_privilege then null; end;
  begin perform public.save_employee_progress('b6000000-0000-4000-8000-000000000001','e6000000-0000-4000-8000-000000000001',10,true); raise exception 'Revoked progress write accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.profiles; raise exception 'Revoked direct profile read accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.courses; raise exception 'Revoked direct course read accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.lesson_progress; raise exception 'Revoked direct progress read accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.notification_preferences; raise exception 'Revoked direct preference read accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.session_contexts where session_id='f6000000-0000-4000-8000-000000000002') then
    raise exception 'Revocation mutated context data before denial';
  end if;
end $$;

-- Direct Storage API access also requires a live session.
delete from auth.sessions where id='f6000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
do $$ begin
  begin insert into storage.objects(bucket_id,name) values ('educador-public','covers/revoked.webp');
    raise exception 'Revoked storage write accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from storage.objects where bucket_id='educador-public';
    raise exception 'Revoked storage read accepted'; exception when insufficient_privilege then null; end;
end $$;

-- Wrong user, unknown and malformed session IDs fail closed.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'Wrong-user session accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.profiles; raise exception 'Wrong-user session read profiles'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000009","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'Unknown session accepted'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"not-a-uuid","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'Malformed session accepted'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
do $$ begin
  begin perform public.context_role(); raise exception 'Missing session accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.profiles; raise exception 'Missing session read profiles'; exception when insufficient_privilege then null; end;
end $$;

-- A fresh Auth session restores access without any client-side repair step.
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000002","session_id":"f6000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
select public.select_context('funcionario','b6000000-0000-4000-8000-000000000001');
do $$ begin
  if public.context_role() <> 'funcionario' then raise exception 'New session could not reselect'; end if;
end $$;

-- Service-role certificate issuance trusts the session only when it is live.
reset role;
set local role service_role;
do $$ declare result jsonb; begin
  result := issue_employee_certificate('a6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000003','b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001');
  if (result->>'created')::boolean is not true then raise exception 'Live certificate issuance failed'; end if;
  begin perform issue_employee_certificate('a6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001');
    raise exception 'Revoked certificate issuance accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform issue_employee_certificate('a6000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000003','b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001');
    raise exception 'Wrong-user certificate issuance accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform issue_employee_certificate('a6000000-0000-4000-8000-000000000002',null,'b6000000-0000-4000-8000-000000000001','c6000000-0000-4000-8000-000000000001');
    raise exception 'Missing certificate session accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;

-- Service-role push claims revalidate the session before claiming or reading.
reset role;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('f6000000-0000-4000-8000-000000000006','a6000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a6000000-0000-4000-8000-000000000001","session_id":"f6000000-0000-4000-8000-000000000006","aal":"aal1"}',true);
select public.select_context('gestor',null);
reset role;
update public.courses set status='released', push_pending_at=now() where id='c6000000-0000-4000-8000-000000000001';
set local role service_role;
do $$ declare r jsonb; begin
  r := claim_push_recipients('a6000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000006','course_available','c6000000-0000-4000-8000-000000000001',null,null);
  if (r->>'suppressed')::boolean then raise exception 'Live push claim suppressed'; end if;
  update public.courses set push_pending_at=now(), push_claimed_at=null where id='c6000000-0000-4000-8000-000000000001';
  begin perform claim_push_recipients('a6000000-0000-4000-8000-000000000001','f6000000-0000-4000-8000-000000000002','course_available','c6000000-0000-4000-8000-000000000001',null,null);
    raise exception 'Revoked push claim accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  if (select push_pending_at from public.courses where id='c6000000-0000-4000-8000-000000000001') is null then
    raise exception 'Revoked push claim mutated course state';
  end if;
end $$;

-- Invitation acceptance: live session grants, revoked/mismatched session denies
-- before the token is consumed.
reset role;
insert into membership_invites(email,role,company_id,token_hash,expires_at) values
 ('revoked-employee@example.test','empresa','b6000000-0000-4000-8000-000000000001',repeat('6',64),now()+interval '1 hour'),
 ('revoked-employee@example.test','funcionario','b6000000-0000-4000-8000-000000000001',repeat('7',64),now()+interval '1 hour');
set local role service_role;
do $$ begin
  begin perform accept_membership_invite(repeat('6',64),'a6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000002','revoked-employee@example.test');
    raise exception 'Revoked invitation acceptance accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform accept_membership_invite(repeat('6',64),'a6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000006','revoked-employee@example.test');
    raise exception 'Mismatched invitation acceptance accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform accept_membership_invite(repeat('6',64),'a6000000-0000-4000-8000-000000000002',null,'revoked-employee@example.test');
    raise exception 'Missing invitation session accepted'; exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform accept_membership_invite(repeat('6',64),'a6000000-0000-4000-8000-000000000002','revoked-employee@example.test');
    raise exception 'Legacy invitation signature accepted'; exception when insufficient_privilege then null; end;
  perform accept_membership_invite(repeat('6',64),'a6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000003','revoked-employee@example.test');
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.company_memberships where user_id='a6000000-0000-4000-8000-000000000002'
      and company_id='b6000000-0000-4000-8000-000000000001' and role='empresa') then
    raise exception 'Live invitation acceptance failed'; end if;
  if exists(select 1 from public.membership_invites where token_hash=repeat('6',64)) then
    raise exception 'Live invitation token not consumed'; end if;
  if not exists(select 1 from public.membership_invites where token_hash=repeat('7',64)) then
    raise exception 'Denied attempts consumed an invitation token'; end if;
end $$;
rollback;
