-- EducaDor foundation: tables. Spec: stack/01-backend.md
-- Apply: supabase db push (linked project) or paste in SQL editor.
-- Region: sa-east-1. Staging lives on the 2nd free project.

create extension if not exists "pgcrypto";

-- ---- Tenancy root ----
create table companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  cnpj text unique,
  code_prefix text not null default 'EDU',
  responsible text,
  email text,
  phone text,
  address text,
  city text,
  state text,
  field text,
  active bool not null default true,
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('gestor', 'empresa', 'funcionario')),
  company_id uuid references companies (id),
  full_name text not null,
  email text not null,
  avatar_key text,
  dept text,
  job_title text,
  phone text,
  birth_date date,
  address text
);

-- ---- Catalog ----
create table courses (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null default 'course',
  cover_key text,
  description text,
  status text not null default 'released',
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references courses (id) on delete cascade,
  title text not null,
  position int not null default 0
);

create table lessons (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references modules (id) on delete cascade,
  title text not null,
  kind text not null check (kind in ('video', 'audio', 'pdf', 'quiz', 'reading')),
  video_provider text not null default 'youtube' check (video_provider = 'youtube'),
  video_id text,
  file_key text,
  points int not null default 10, -- per-task value set by gestor, no universal rule
  quiz_json jsonb,
  position int not null default 0
);

-- "Liberar para:" – which companies get which course
create table assignments (
  course_id uuid not null references courses (id) on delete cascade,
  company_id uuid not null references companies (id) on delete cascade,
  released bool not null default true,
  primary key (course_id, company_id)
);

-- ---- Progress / gamification (derived balances, no ledger, no triggers) ----
create table lesson_progress (
  user_id uuid not null references profiles (id) on delete cascade,
  lesson_id uuid not null references lessons (id) on delete cascade,
  status text not null default 'in_progress' check (status in ('locked', 'in_progress', 'completed')),
  score int,
  position_sec int not null default 0, -- resume point for video/audio
  updated_at timestamptz not null default now(),
  primary key (user_id, lesson_id)
);

create table certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  course_id uuid not null references courses (id) on delete cascade,
  code text not null unique, -- {companies.code_prefix}-{6-char Crockford base32}
  issued_at timestamptz not null default now(),
  unique (user_id, course_id) -- one certificate per user per course
);

create table rewards (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  points_cost int not null check (points_cost > 0),
  active bool not null default true
);

create table redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  reward_id uuid not null references rewards (id),
  created_at timestamptz not null default now()
);

create table fcm_tokens (
  user_id uuid not null references profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- ---- Storage buckets (files share the 1GB quota; video is YouTube-only) ----
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('educador-public', 'educador-public', true, 52428800,
    array['image/webp', 'image/png', 'image/jpeg']),
  ('educador-private', 'educador-private', false, 52428800,
    array['application/pdf', 'audio/mpeg', 'audio/mp3', 'audio/x-m4a']),
  ('educador-backups', 'educador-backups', false, 52428800,
    array['application/gzip', 'application/sql', 'application/octet-stream'])
on conflict (id) do nothing;
