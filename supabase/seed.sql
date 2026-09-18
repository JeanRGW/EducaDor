-- EducaDor seed (staging/dev only – never run on prod).
-- Mapped from lib/data/mock/mock_data.dart (intentionally minimal: inactive
-- mock companies such as Oftalmo Vale are omitted).
--
-- 1. Create the 3 users first, via Dashboard > Auth > Users or the Auth Admin
--    API: gestor@educador.com / empresa@educador.com / joao.silva@santamaria.com
--    (share the throwaway password out-of-band; rotate on first login).
--    Never commit real credentials – AGENTS.md forbids secrets in the repo.
-- 2. Run this file via SQL editor or supabase db reset.
-- Profiles resolve user IDs by email lookup, so no hardcoded auth UUIDs.

-- ---- companies ----
insert into companies (id, name, cnpj, code_prefix, responsible, email, phone,
  address, city, state, field, active)
values
  ('10000000-0000-4000-8000-000000000001', 'Grupo Santa Maria', '12.345.678/0001-90',
   'GSM', 'Elen Guimarães', 'admin@santamaria.com', '(31) 99999-9999',
   'Rua das Flores, 120', 'Belo Horizonte', 'MG', 'Operações', true),
  ('10000000-0000-4000-8000-000000000002', 'Unimed Belo Horizonte', '98.765.432/0001-10',
   'UNIMED', 'Elen Guimarães', 'admin@unimedbh.com', '(31) 98888-8888',
   'Av. do Contorno, 500', 'Belo Horizonte', 'MG', 'Saúde', true)
on conflict (id) do nothing;

-- ---- profiles (role + company shape matches session_controller.dart) ----
insert into profiles (id, role, company_id, full_name, email, dept, job_title)
select u.id, 'gestor', null,
  'Nome Gestor', 'gestor@educador.com', null, null
from auth.users u where u.email = 'gestor@educador.com'
on conflict (id) do nothing;

insert into profiles (id, role, company_id, full_name, email, dept, job_title)
select u.id, 'empresa', '10000000-0000-4000-8000-000000000001',
  'Grupo Santa Maria', 'empresa@educador.com', null, null
from auth.users u where u.email = 'empresa@educador.com'
on conflict (id) do nothing;

insert into profiles (id, role, company_id, full_name, email, dept, job_title)
select u.id, 'funcionario', '10000000-0000-4000-8000-000000000001',
  'João Silva', 'joao.silva@santamaria.com',
  'Departamento de Operações', 'Auxiliar de Operações'
from auth.users u where u.email = 'joao.silva@santamaria.com'
on conflict (id) do nothing;

-- ---- catalog: one course, one module, four lessons (mirrors mock mod-1) ----
insert into courses (id, title, kind, description, status, created_by)
select '20000000-0000-4000-8000-000000000001', 'Segurança no trabalho', 'course',
  'Aprenda os principais conceitos de segurança do trabalho, prevenção de acidentes e cuidados necessários para manter um ambiente de trabalho seguro e saudável.',
  'released', u.id
from auth.users u where u.email = 'gestor@educador.com'
on conflict (id) do nothing;

insert into modules (id, course_id, title, position)
values ('21000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', 'Segurança no trabalho', 1)
on conflict (id) do nothing;

insert into lessons (id, module_id, title, kind, video_provider, video_id, points, position)
values
  ('22000000-0000-4000-8000-000000000001',
   '21000000-0000-4000-8000-000000000001',
   'Módulo 1: Introdução', 'reading', 'youtube', null, 10, 1),
  ('22000000-0000-4000-8000-000000000002',
   '21000000-0000-4000-8000-000000000001',
   'Vídeo', 'video', 'youtube', null, 10, 2),
  ('22000000-0000-4000-8000-000000000003',
   '21000000-0000-4000-8000-000000000001',
   'Quiz', 'quiz', 'youtube', null, 20, 3),
  ('22000000-0000-4000-8000-000000000004',
   '21000000-0000-4000-8000-000000000001',
   'Conversar com profissional', 'reading', 'youtube', null, 10, 4)
on conflict (id) do nothing;
-- NOTE: video lessons ship with null video_id in seed; paste a real YouTube ID when testing playback.

-- "Liberar para:" Santa Maria
insert into assignments (course_id, company_id, released)
values ('20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001', true)
on conflict do nothing;

-- ---- progress: João completed lesson 1 (10 pts), in progress on lesson 2 ----
insert into lesson_progress (user_id, lesson_id, status, score, updated_at)
select u.id, '22000000-0000-4000-8000-000000000001', 'completed', null, now()
from auth.users u where u.email = 'joao.silva@santamaria.com'
on conflict do nothing;

insert into lesson_progress (user_id, lesson_id, status, score, updated_at)
select u.id, '22000000-0000-4000-8000-000000000002', 'in_progress', null, now()
from auth.users u where u.email = 'joao.silva@santamaria.com'
on conflict do nothing;

-- ---- rewards catalog (global per mocks) ----
insert into rewards (id, title, points_cost, active)
values
  ('30000000-0000-4000-8000-000000000001', 'Vale café', 300, true),
  ('30000000-0000-4000-8000-000000000002', 'Caneta térmica', 500, true),
  ('30000000-0000-4000-8000-000000000003', 'Headset', 900, true),
  ('30000000-0000-4000-8000-000000000004', 'Cartão-presente', 1200, true)
on conflict (id) do nothing;
