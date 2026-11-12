-- Isolated database only; fixtures roll back. No production data is used.
begin;
do $$ declare signature text; begin
  foreach signature in array array['public.gestor_completion_export(uuid)',
    'public.company_completion_export(uuid,uuid)'] loop
    if has_function_privilege('anon', signature, 'EXECUTE') or
      not has_function_privilege('authenticated', signature, 'EXECUTE') or
      has_function_privilege('service_role', signature, 'EXECUTE') then
      raise exception 'Incorrect export grants: %', signature;
    end if;
  end loop;
end $$;
insert into auth.users(id, email)
select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'export-' || n || '@example.test'
from generate_series(1, 53) n;
insert into profiles(id, full_name, email)
select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'Employee ' || lpad(n::text, 3, '0'),
  'export-' || n || '@example.test'
from generate_series(1, 53) n;
insert into auth.users(id, email) values
  ('a8000000-0000-4000-8000-000000000100', 'export-gestor@example.test');
insert into profiles(id, full_name, email) values
  ('a8000000-0000-4000-8000-000000000100', 'Export Gestor', 'export-gestor@example.test');
insert into platform_gestors(user_id) values ('a8000000-0000-4000-8000-000000000100');
insert into auth.sessions(id, user_id, created_at, updated_at, not_after) values
  ('f8000000-0000-4000-8000-000000000001', 'a8000000-0000-4000-8000-000000000100', now(), now(), now() + interval '1 day'),
  ('f8000000-0000-4000-8000-000000000002', 'a8000000-0000-4000-8000-000000000002', now(), now(), now() + interval '1 day'),
  ('f8000000-0000-4000-8000-000000000003', 'a8000000-0000-4000-8000-000000000001', now(), now(), now() + interval '1 day');
insert into companies(id, name)
select ('b8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'Export Company ' || lpad(n::text, 3, '0')
from generate_series(1, 101) n;
-- Company 1 has 52 employees (two export pages); company 2 has one.
insert into company_memberships(user_id, company_id, role, dept)
select ('a8000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'b8000000-0000-4000-8000-000000000001', 'funcionario', 'Ops'
from generate_series(1, 52) n;
insert into company_memberships(user_id, company_id, role, dept)
values ('a8000000-0000-4000-8000-000000000001',
  'b8000000-0000-4000-8000-000000000002', 'funcionario', 'TI');
insert into company_memberships(user_id, company_id, role)
values ('a8000000-0000-4000-8000-000000000002',
  'b8000000-0000-4000-8000-000000000002', 'empresa');
insert into courses(id, title, all_companies) values
  ('c8000000-0000-4000-8000-000000000001', 'Export course', true);
insert into modules(id, course_id, title) values
  ('d8000000-0000-4000-8000-000000000001', 'c8000000-0000-4000-8000-000000000001', 'Module');
insert into lessons(id, module_id, title, kind) values
  ('e8000000-0000-4000-8000-000000000001', 'd8000000-0000-4000-8000-000000000001', 'One', 'reading'),
  ('e8000000-0000-4000-8000-000000000002', 'd8000000-0000-4000-8000-000000000001', 'Two', 'reading');
insert into lesson_progress(user_id, company_id, lesson_id, status) values
  ('a8000000-0000-4000-8000-000000000001', 'b8000000-0000-4000-8000-000000000001',
    'e8000000-0000-4000-8000-000000000001', 'completed');
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000100","session_id":"f8000000-0000-4000-8000-000000000001"}', true);
select select_context('gestor');
do $$ declare p jsonb; a uuid; b uuid; total int; begin
  p := gestor_completion_export();
  total := (p->>'total_count')::int;
  if total <> 101 or jsonb_array_length(p->'items') <> 50 then
    raise exception 'First gestor export page wrong: %', p;
  end if;
  a := (p->'items'->0->>'company_id')::uuid;
  b := (p->'items'->49->>'company_id')::uuid;
  if a >= b then raise exception 'Gestor export order unstable'; end if;
  if (p->'items'->0->>'company_id')::uuid <> 'b8000000-0000-4000-8000-000000000001' then
    raise exception 'Gestor export did not start at first company';
  end if;
  if (p->'items'->0->>'pct')::numeric <> 1.0 then
    raise exception 'Gestor export aggregate mismatch: %', p->'items'->0;
  end if;
  if (select count(*) from jsonb_array_elements(p->'items') r where r->>'pct' is null) <> 48 then
    raise exception 'No-data companies were converted to zero';
  end if;
  p := gestor_completion_export(b);
  if (p->>'total_count')::int <> 101 or jsonb_array_length(p->'items') <> 50 then
    raise exception 'Second gestor export page wrong';
  end if;
  if (p->'items'->0->>'company_id')::uuid <= b then
    raise exception 'Gestor cursor repeated or moved backwards';
  end if;
  p := gestor_completion_export((p->'items'->49->>'company_id')::uuid);
  if (p->>'total_count')::int <> 101 or jsonb_array_length(p->'items') <> 1 then
    raise exception 'Final gestor export page wrong';
  end if;
end $$;
reset role;
insert into auth.mfa_factors(id, user_id, factor_type, status, created_at, updated_at)
values ('f8000000-0000-4000-8000-000000000010',
  'a8000000-0000-4000-8000-000000000100', 'totp', 'verified', now(), now());
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000100","session_id":"f8000000-0000-4000-8000-000000000001","aal":"aal1"}', true);
do $$ begin
  begin perform gestor_completion_export();
    raise exception 'AAL1 export accepted';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000100","session_id":"f8000000-0000-4000-8000-000000000001","aal":"aal2"}', true);
do $$ begin
  if (gestor_completion_export()->>'total_count')::int <> 101 then
    raise exception 'AAL2 export failed';
  end if;
end $$;
reset role;
delete from auth.mfa_factors where user_id = 'a8000000-0000-4000-8000-000000000100';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000100","session_id":"f8000000-0000-4000-8000-000000000001"}', true);
select select_context('gestor');
do $$ declare p jsonb; total int; last uuid; begin
  -- Employee export is company-scoped and paginates by user_id, not offset.
  p := company_completion_export('b8000000-0000-4000-8000-000000000001');
  total := (p->>'total_count')::int;
  if total <> 52 or jsonb_array_length(p->'items') <> 50 then
    raise exception 'First employee export page wrong: %', p;
  end if;
  if (p->'items'->0->>'pct')::numeric <> 50.0 then
    raise exception 'Employee export aggregate mismatch: %', p->'items'->0;
  end if;
  last := (p->'items'->49->>'user_id')::uuid;
  p := company_completion_export('b8000000-0000-4000-8000-000000000001', last);
  if (p->>'total_count')::int <> 52 or jsonb_array_length(p->'items') <> 2 then
    raise exception 'Final employee export page wrong';
  end if;
  if (p->'items'->0->>'user_id')::uuid <= last then
    raise exception 'Employee cursor repeated or moved backwards';
  end if;
end $$;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000002","session_id":"f8000000-0000-4000-8000-000000000002"}', true);
select select_context('empresa', 'b8000000-0000-4000-8000-000000000002');
do $$ begin
  begin perform company_completion_export('b8000000-0000-4000-8000-000000000001');
    raise exception 'Cross-company export accepted';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
  begin perform gestor_completion_export();
    raise exception 'Company context accepted platform export';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000001","session_id":"f8000000-0000-4000-8000-000000000003"}', true);
select select_context('funcionario', 'b8000000-0000-4000-8000-000000000001');
do $$ begin
  begin perform company_completion_export('b8000000-0000-4000-8000-000000000001');
    raise exception 'Employee context accepted company export';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
delete from platform_gestors where user_id = 'a8000000-0000-4000-8000-000000000100';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a8000000-0000-4000-8000-000000000100","session_id":"f8000000-0000-4000-8000-000000000001"}', true);
do $$ begin
  begin perform gestor_completion_export(); raise exception 'Revoked gestor accepted export';
  exception when raise_exception then if sqlerrm <> 'Forbidden' then raise; end if; end;
end $$;
reset role;
rollback;
