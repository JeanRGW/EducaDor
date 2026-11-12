begin;
insert into auth.users(id,email) values
 ('a9000000-0000-4000-8000-000000000001','manager-privacy@example.test'),
 ('a9000000-0000-4000-8000-000000000002','employee-privacy@example.test'),
 ('a9000000-0000-4000-8000-000000000003','other-privacy@example.test');
insert into public.profiles(id,full_name,email,phone,birth_date,address,gender) values
 ('a9000000-0000-4000-8000-000000000001','Manager','manager-privacy@example.test','manager phone','1990-01-01','manager address','female'),
 ('a9000000-0000-4000-8000-000000000002','Employee','employee-privacy@example.test','employee phone','1991-01-01','employee address','male'),
 ('a9000000-0000-4000-8000-000000000003','Other','other-privacy@example.test','other phone','1992-01-01','other address',null);
insert into public.companies(id,name) values
 ('b9000000-0000-4000-8000-000000000001','Company'),
 ('b9000000-0000-4000-8000-000000000002','Other company');
insert into public.company_memberships(user_id,company_id,role) values
 ('a9000000-0000-4000-8000-000000000001','b9000000-0000-4000-8000-000000000001','empresa'),
 ('a9000000-0000-4000-8000-000000000002','b9000000-0000-4000-8000-000000000001','funcionario'),
 ('a9000000-0000-4000-8000-000000000003','b9000000-0000-4000-8000-000000000002','funcionario');
insert into public.platform_gestors(user_id) values ('a9000000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"a9000000-0000-4000-8000-000000000004","aal":"aal1"}',true);
select public.select_context('empresa','b9000000-0000-4000-8000-000000000001');
do $$ declare c text; target uuid; begin
  foreach c in array array['phone','birth_date','address','gender'] loop
    foreach target in array array['a9000000-0000-4000-8000-000000000001'::uuid,'a9000000-0000-4000-8000-000000000002'::uuid,'a9000000-0000-4000-8000-000000000003'::uuid] loop
      begin execute format('select %I from public.profiles where id = $1', c) using target;
        raise exception 'Sensitive column % exposed for %', c, target;
      exception when insufficient_privilege then null; end;
    end loop;
  end loop;
  if (select count(*) from public.profiles where id='a9000000-0000-4000-8000-000000000002') <> 1 then raise exception 'Directory unavailable'; end if;
  if (select count(*) from public.profiles where id='a9000000-0000-4000-8000-000000000003') <> 0 then raise exception 'Cross-company directory exposed'; end if;
  if not exists(select 1 from public.own_profile() where phone='manager phone' and birth_date='1990-01-01' and address='manager address' and gender='female') then raise exception 'Own profile unavailable'; end if;
end $$;
select public.select_context('gestor',null);
do $$ begin
  begin perform phone from public.profiles; raise exception 'Gestor sensitive column exposed'; exception when insufficient_privilege then null; end;
  if (select count(*) from public.profiles where id='a9000000-0000-4000-8000-000000000003') <> 1 then raise exception 'Gestor directory unavailable'; end if;
  if (select count(*) from public.own_profile()) <> 1 then raise exception 'Gestor own profile unavailable'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000002","session_id":"a9000000-0000-4000-8000-000000000006","aal":"aal1"}',true);
select public.select_context('funcionario','b9000000-0000-4000-8000-000000000001');
do $$ begin
  if not exists(select 1 from public.own_profile() where phone='employee phone' and gender='male') then raise exception 'Employee own profile unavailable'; end if;
  if (select count(*) from public.own_profile()) <> 1 then raise exception 'Other profile exposed'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.own_profile(); raise exception 'Anonymous profile access'; exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at) values ('a9000000-0000-4000-8000-000000000005','a9000000-0000-4000-8000-000000000001','totp','verified',now(),now());
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"a9000000-0000-4000-8000-000000000004","aal":"aal1"}',true);
do $$ begin
  begin perform public.own_profile(); raise exception 'MFA bypass'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"a9000000-0000-4000-8000-000000000001","session_id":"a9000000-0000-4000-8000-000000000004","aal":"aal2"}',true);
do $$ begin if (select count(*) from public.own_profile()) <> 1 then raise exception 'AAL2 own profile unavailable'; end if; end $$;
rollback;
