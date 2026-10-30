SET local check_function_bodies = off;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "service_role";

CREATE TABLE "public"."assignments" (
  "course_id"       uuid    NOT NULL,
  "company_id"      uuid    NOT NULL,
  "released"        boolean NOT NULL DEFAULT true,
  "company_enabled" boolean NOT NULL DEFAULT true,
  CONSTRAINT "assignments_pkey" PRIMARY KEY (course_id, company_id)
);

ALTER TABLE "public"."assignments"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."assignments" FROM "anon";

CREATE TABLE "public"."certificates" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "course_id"  uuid                     NOT NULL,
  "code"       text                     NOT NULL,
  "issued_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "company_id" uuid                     NOT NULL,
  CONSTRAINT "certificates_code_key" UNIQUE (code),
  CONSTRAINT "certificates_pkey" PRIMARY KEY (id),
  CONSTRAINT "certificates_user_id_company_id_course_id_key" UNIQUE (user_id, company_id, course_id)
);

ALTER TABLE "public"."certificates"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."certificates" FROM "anon";

CREATE TABLE "public"."companies" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"        text                     NOT NULL,
  "cnpj"        text,
  "code_prefix" text                     NOT NULL DEFAULT 'EDU'::text,
  "responsible" text,
  "email"       text,
  "phone"       text,
  "address"     text,
  "city"        text,
  "state"       text,
  "field"       text,
  "active"      boolean                  NOT NULL DEFAULT true,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "companies_cnpj_key" UNIQUE (cnpj),
  CONSTRAINT "companies_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."companies"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."companies" FROM "anon";

CREATE TABLE "public"."company_memberships" (
  "user_id"    uuid NOT NULL,
  "company_id" uuid NOT NULL,
  "role"       text NOT NULL,
  "dept"       text,
  "job_title"  text,
  CONSTRAINT "company_memberships_pkey" PRIMARY KEY (user_id, company_id, ROLE),
  CONSTRAINT "company_memberships_role_check" CHECK ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text])))
);

ALTER TABLE "public"."company_memberships"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."company_memberships" FROM "anon";

CREATE TABLE "public"."courses" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "title"          text                     NOT NULL,
  "kind"           text                     NOT NULL DEFAULT 'course'::text,
  "cover_key"      text,
  "description"    text,
  "status"         text                     NOT NULL DEFAULT 'released'::text,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "all_companies"  boolean                  NOT NULL DEFAULT true,
  "responsible_id" uuid,
  CONSTRAINT "courses_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."courses"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."courses" FROM "anon";

CREATE TABLE "public"."fcm_tokens" (
  "user_id"    uuid                     NOT NULL,
  "token"      text                     NOT NULL,
  "platform"   text                     NOT NULL DEFAULT 'android'::text,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "fcm_tokens_pkey" PRIMARY KEY (user_id, token)
);

ALTER TABLE "public"."fcm_tokens"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."fcm_tokens" FROM "anon";

CREATE TABLE "public"."lesson_progress" (
  "user_id"      uuid                     NOT NULL,
  "lesson_id"    uuid                     NOT NULL,
  "status"       text                     NOT NULL DEFAULT 'in_progress'::text,
  "score"        integer,
  "position_sec" integer                  NOT NULL DEFAULT 0,
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "company_id"   uuid                     NOT NULL,
  CONSTRAINT "lesson_progress_pkey" PRIMARY KEY (user_id, company_id, lesson_id),
  CONSTRAINT "lesson_progress_status_check" CHECK ((status = ANY (ARRAY['locked'::text, 'in_progress'::text, 'completed'::text])))
);

ALTER TABLE "public"."lesson_progress"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."lesson_progress" FROM "anon";

CREATE TABLE "public"."lessons" (
  "id"             uuid    NOT NULL DEFAULT gen_random_uuid(),
  "module_id"      uuid    NOT NULL,
  "title"          text    NOT NULL,
  "kind"           text    NOT NULL,
  "video_provider" text    NOT NULL DEFAULT 'youtube'::text,
  "video_id"       text,
  "file_key"       text,
  "points"         integer NOT NULL DEFAULT 10,
  "quiz_json"      jsonb,
  "position"       integer NOT NULL DEFAULT 0,
  "body"           text    NOT NULL DEFAULT ''::text,
  "image_keys"     text[]  NOT NULL DEFAULT '{}'::text[],
  "frame_ms"       integer NOT NULL DEFAULT 1000,
  CONSTRAINT "lessons_frame_ms_check" CHECK (((frame_ms >= 100) AND (frame_ms <= 10000))),
  CONSTRAINT "lessons_kind_check" CHECK ((kind = ANY (ARRAY['video'::text, 'audio'::text, 'pdf'::text, 'quiz'::text, 'reading'::text, 'animation'::text]))),
  CONSTRAINT "lessons_pkey" PRIMARY KEY (id),
  CONSTRAINT "lessons_video_provider_check" CHECK ((video_provider = 'youtube'::text))
);

ALTER TABLE "public"."lessons"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."lessons" FROM "anon";

CREATE TABLE "public"."membership_invites" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "email"      text                     NOT NULL,
  "role"       text                     NOT NULL,
  "company_id" uuid,
  "dept"       text,
  "job_title"  text,
  "invited_by" uuid,
  "token_hash" text                     NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invite_scope" CHECK ((((role = 'gestor'::text) AND (company_id IS NULL)) OR ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text])) AND (company_id IS
    NOT NULL)))),
  CONSTRAINT "membership_invites_pkey" PRIMARY KEY (id),
  CONSTRAINT "membership_invites_role_check" CHECK ((role = ANY (ARRAY['gestor'::text, 'empresa'::text, 'funcionario'::text]))),
  CONSTRAINT "membership_invites_token_hash_check" CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "membership_invites_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "public"."membership_invites"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."membership_invites" FROM "anon", "authenticated";

CREATE TABLE "public"."modules" (
  "id"        uuid    NOT NULL DEFAULT gen_random_uuid(),
  "course_id" uuid    NOT NULL,
  "title"     text    NOT NULL,
  "position"  integer NOT NULL DEFAULT 0,
  CONSTRAINT "modules_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."modules"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."modules" FROM "anon";

CREATE TABLE "public"."platform_gestors" (
  "user_id" uuid NOT NULL,
  CONSTRAINT "platform_gestors_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."platform_gestors"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."platform_gestors" FROM "anon";

CREATE TABLE "public"."profiles" (
  "id"             uuid    NOT NULL,
  "full_name"      text    NOT NULL,
  "email"          text    NOT NULL,
  "avatar_key"     text,
  "phone"          text,
  "birth_date"     date,
  "address"        text,
  "needs_password" boolean NOT NULL DEFAULT false,
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

CREATE TABLE "public"."redemptions" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "reward_id"  uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "company_id" uuid                     NOT NULL,
  CONSTRAINT "redemptions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."redemptions"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."redemptions" FROM "anon";

CREATE TABLE "public"."rewards" (
  "id"          uuid    NOT NULL DEFAULT gen_random_uuid(),
  "title"       text    NOT NULL,
  "points_cost" integer NOT NULL,
  "active"      boolean NOT NULL DEFAULT true,
  CONSTRAINT "rewards_pkey" PRIMARY KEY (id),
  CONSTRAINT "rewards_points_cost_check" CHECK ((points_cost > 0))
);

ALTER TABLE "public"."rewards"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."rewards" FROM "anon";

CREATE TABLE "public"."session_contexts" (
  "session_id" uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "role"       text                     NOT NULL,
  "company_id" uuid,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "context_scope" CHECK ((((role = 'gestor'::text) AND (company_id IS NULL)) OR ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text])) AND (company_id IS
    NOT NULL)))),
  CONSTRAINT "session_contexts_pkey" PRIMARY KEY (session_id),
  CONSTRAINT "session_contexts_role_check" CHECK ((role = ANY (ARRAY['gestor'::text, 'empresa'::text, 'funcionario'::text])))
);

ALTER TABLE "public"."session_contexts"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."session_contexts" FROM "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.accept_membership_invite (
  p_token_hash text,
  p_user       uuid,
  p_email      text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare invite public.membership_invites;
begin
  lock table public.platform_gestors in share row exclusive mode;
  lock table public.company_memberships in share row exclusive mode;
  select * into invite from public.membership_invites
    where token_hash = p_token_hash and lower(email) = lower(p_email)
      and expires_at > now() for update;
  if not found or not exists (select 1 from public.profiles
    where id = p_user and lower(email) = lower(p_email)) then
    raise exception 'Invitation unavailable';
  end if;
  if invite.company_id is not null and not exists (
    select 1 from public.companies where id = invite.company_id and active) then
    raise exception 'Company unavailable';
  end if;
  if invite.role = 'gestor' then
    insert into public.platform_gestors(user_id) values (p_user) on conflict do nothing;
  else
    insert into public.company_memberships(user_id, company_id, role, dept, job_title)
      values (p_user, invite.company_id, invite.role, invite.dept, invite.job_title)
      on conflict (user_id, company_id, role) do update
        set dept = excluded.dept, job_title = excluded.job_title;
  end if;
  delete from public.membership_invites where id = invite.id;
end $function$;

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.available_contexts()
  RETURNS TABLE (
    role         text,
    company_id   uuid,
    company_name text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select 'gestor'::text, null::uuid, 'Plataforma'::text
  from public.platform_gestors where user_id = (select auth.uid())
  union all
  select cm.role, cm.company_id, c.name from public.company_memberships cm
    join public.companies c on c.id = cm.company_id and c.active
  where cm.user_id = (select auth.uid())
  order by 1, 3
$function$;

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.clear_context()
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  delete from public.session_contexts
  where user_id = (select auth.uid())
    and session_id = nullif(auth.jwt()->>'session_id', '')::uuid
$function$;

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.company_dashboard (
  p_company uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'empresa' and
    p_company = public.own_company_id(), false) then raise exception 'Forbidden'; end if;
  with employees as (
    select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title
    from public.company_memberships cm join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company and cm.role = 'funcionario'
  ), months as (
    select generate_series(date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '5 months',
      date_trunc('month', now() at time zone 'America/Sao_Paulo'), interval '1 month')::date as month
  ), engagement as (
    select month, count(distinct lp.user_id) as active_users
    from months left join public.lesson_progress lp on lp.company_id = p_company
      and lp.updated_at >= (month::timestamp at time zone 'America/Sao_Paulo')
      and lp.updated_at < ((month + interval '1 month') at time zone 'America/Sao_Paulo')
      and lp.updated_at <= now() and exists(select 1 from employees e where e.user_id = lp.user_id)
    group by month
  ), completions as (
    select e.user_id, e.full_name, e.email, e.dept, e.job_title,
      round(100.0 * count(l.id) filter (where lp.status = 'completed') / nullif(count(l.id), 0), 1) as pct
    from employees e
    left join public.courses c on public.course_company_allowed(c.id, p_company)
    left join public.modules m on m.course_id = c.id
    left join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.user_id = e.user_id
      and lp.company_id = p_company and lp.lesson_id = l.id
    group by e.user_id, e.full_name, e.email, e.dept, e.job_title
  ), highlights as (
    select * from completions where pct > 0
    order by pct desc, lower(full_name), user_id limit 2
  )
  select jsonb_build_object(
    'employee_count', (select count(*) from employees),
    'active_course_count', (select count(*) from public.courses c
      where c.status = 'released' and public.course_company_allowed(c.id, p_company)
        and coalesce((select a.company_enabled from public.assignments a
          where a.course_id = c.id and a.company_id = p_company), true)),
    'certificate_count', (select count(*) from public.certificates where company_id = p_company),
    'completion_pct', (select pct from public.completion_by_company where company_id = p_company),
    'engagement', (select jsonb_agg(to_jsonb(e) order by month) from engagement e),
    'highlights', coalesce((select jsonb_agg(to_jsonb(h) order by pct desc, lower(full_name), user_id)
      from highlights h), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."company_dashboard"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.company_employees (
  p_company uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'empresa' and
    p_company = public.own_company_id(), false) then raise exception 'Forbidden'; end if;
  with employees as (
    select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title
    from public.company_memberships cm join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company and cm.role = 'funcionario'
  ), matching as (
    select * from employees where
      strpos(lower(full_name), lower(trim(coalesce(p_search, '')))) > 0 or
      strpos(lower(coalesce(dept, '')), lower(trim(coalesce(p_search, '')))) > 0
  ), page as (
    select * from matching order by lower(full_name), user_id
    limit 50 offset greatest(coalesce(p_offset, 0), 0)
  ), items as (
    select e.*,
      (select round(100.0 * count(*) filter (where lp.status = 'completed') / nullif(count(*), 0), 1)
        from public.courses c join public.modules m on m.course_id = c.id
        join public.lessons l on l.module_id = m.id
        left join public.lesson_progress lp on lp.lesson_id = l.id
          and lp.user_id = e.user_id and lp.company_id = p_company
        where public.course_company_allowed(c.id, p_company)) as pct,
      (select max(lp.updated_at) from public.lesson_progress lp
        where lp.user_id = e.user_id and lp.company_id = p_company
          and lp.updated_at <= now()) as last_activity_at
    from page e
  )
  select jsonb_build_object(
    'total_count', (select count(*) from employees),
    'filtered_count', (select count(*) from matching),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by lower(full_name), user_id)
      from items i), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."company_employees"(uuid, text, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.content_catalog (
  p_search text    DEFAULT ''::text,
  p_kind   text    DEFAULT NULL::text,
  p_offset integer DEFAULT 0,
  p_limit  integer DEFAULT 50
)
  RETURNS TABLE (
    id               uuid,
    title            text,
    kind             text,
    description      text,
    cover_key        text,
    platform_enabled boolean,
    all_companies    boolean,
    company_enabled  boolean,
    company_ids      uuid[],
    company_count    bigint,
    lesson_count     bigint,
    completion_pct   numeric,
    module_count     bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare cid uuid := public.own_company_id(); platform boolean := coalesce(public.is_gestor(), false);
begin
  if not platform and (public.context_role() is distinct from 'empresa' or cid is null) then raise exception 'Forbidden'; end if;
  return query with page as (
    select c.* from public.courses c where (platform or public.course_company_allowed(c.id,cid))
      and (p_kind is null or p_kind='course' or exists(select 1 from public.modules m join public.lessons l on l.module_id=m.id where m.course_id=c.id and l.kind=p_kind))
      and (coalesce(p_search,'')='' or strpos(lower(c.title),lower(p_search))>0)
    order by c.created_at desc,c.id limit least(greatest(coalesce(p_limit,50),1),50) offset greatest(coalesce(p_offset,0),0)
  ) select c.id,c.title,c.kind,c.description,c.cover_key,c.status='released',c.all_companies,
    case when platform then true else coalesce((select a.company_enabled from public.assignments a where a.course_id=c.id and a.company_id=cid),true) end,
    case when platform then array(select a.company_id from public.assignments a where a.course_id=c.id and a.released order by a.company_id) else null::uuid[] end,
    case when platform then (select count(*) from public.companies co where co.active and public.course_company_allowed(c.id,co.id)) else 1::bigint end,
    (select count(*) from public.lessons l join public.modules m on m.id=l.module_id where m.course_id=c.id),
    (select round(100.0*count(*) filter(where lp.status='completed')/nullif(count(*),0),1)
      from public.modules m join public.lessons l on l.module_id=m.id
      join public.company_memberships cm on cm.role='funcionario' join public.companies co on co.id=cm.company_id and co.active
      left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=cm.user_id and lp.company_id=cm.company_id
      where m.course_id=c.id and public.course_company_allowed(c.id,cm.company_id) and (platform or cm.company_id=cid)),
    (select count(*) from public.modules m where m.course_id=c.id)
  from page c order by c.created_at desc,c.id;
end $function$;

REVOKE ALL ON FUNCTION "public"."content_catalog"(text, text, integer, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.context_role()
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select sc.role from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and (
      (sc.role = 'gestor' and exists (
        select 1 from public.platform_gestors pg where pg.user_id = sc.user_id))
      or (sc.role in ('empresa', 'funcionario') and exists (
        select 1 from public.company_memberships cm
        join public.companies c on c.id = cm.company_id and c.active
        where cm.user_id = sc.user_id and cm.company_id = sc.company_id
          and cm.role = sc.role))
    )
  limit 1
$function$;

REVOKE ALL ON FUNCTION "public"."context_role"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.course_company_allowed (
  p_course  uuid,
  p_company uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.courses c where c.id = p_course and
      (c.all_companies or exists (
        select 1 from public.assignments a where a.course_id = c.id
          and a.company_id = p_company and a.released)))
$function$;

REVOKE ALL ON FUNCTION "public"."course_company_allowed"(uuid, uuid) FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.create_content_course (
  p_title text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then raise exception 'Invalid title'; end if;
  insert into public.courses(title,kind,status,created_by,all_companies)
    values(trim(p_title),'course','paused',auth.uid(),true) returning id into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."create_content_course"(text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.custom_access_token_hook (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_set(event, '{claims}',
    coalesce(event->'claims', '{}'::jsonb) - 'user_role' - 'company_id')
$function$;

REVOKE ALL ON FUNCTION "public"."custom_access_token_hook"(jsonb) FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.delete_content (
  p_kind text,
  p_id   uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare parent uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_kind='course' then
    delete from public.courses where id=p_id;
  elsif p_kind='module' then
    select course_id into parent from public.modules where id=p_id;
    if not found then raise exception 'Content unavailable'; end if;
    perform 1 from public.courses where id=parent for update;
    delete from public.modules where id=p_id;
  elsif p_kind='lesson' then
    select module_id into parent from public.lessons where id=p_id;
    if not found then raise exception 'Content unavailable'; end if;
    perform 1 from public.modules where id=parent for update;
    delete from public.lessons where id=p_id;
  else raise exception 'Invalid content type';
  end if;
  if not found then raise exception 'Content unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."delete_content"(text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_can_access_course (
  p_course uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(public.context_role() = 'funcionario', false)
    and exists (
      select 1 from public.courses c
      where c.id = p_course and c.status = 'released'
        and public.course_company_allowed(c.id, public.own_company_id())
        and coalesce((select a.company_enabled from public.assignments a
          where a.course_id = c.id and a.company_id = public.own_company_id()), true))
$function$;

REVOKE ALL ON FUNCTION "public"."employee_can_access_course"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_catalog (
  p_company uuid,
  p_search  text    DEFAULT ''::text,
  p_kind    text    DEFAULT NULL::text,
  p_state   text    DEFAULT NULL::text,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset<0 or p_offset is null or (p_kind is not null and p_kind not in ('video','audio','pdf','quiz','reading','animation'))
    or (p_state is not null and p_state not in ('not_started','in_progress','completed')) then raise exception 'Invalid query'; end if;
  with catalog as (
    select c.id,c.title,c.description,c.cover_key,count(l.id)::int as lesson_count,
      count(l.id) filter(where lp.status='completed')::int as completed_count,max(lp.updated_at) as last_activity_at,
      case when count(l.id)>0 and count(l.id)=count(l.id) filter(where lp.status='completed') then 'completed'
        when count(lp.lesson_id)>0 then 'in_progress' else 'not_started' end as state
    from public.courses c left join public.modules m on m.course_id=c.id left join public.lessons l on l.module_id=m.id
    left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=auth.uid() and lp.company_id=p_company
    where public.employee_can_access_course(c.id) and strpos(lower(c.title),lower(trim(coalesce(p_search,''))))>0
      and (p_kind is null or exists(select 1 from public.modules fm join public.lessons fl on fl.module_id=fm.id where fm.course_id=c.id and fl.kind=p_kind))
    group by c.id
  ), matching as (select * from catalog where p_state is null or state=p_state), page as (
    select * from matching order by last_activity_at desc nulls last,lower(title),id limit 50 offset p_offset
  ) select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(p) order by last_activity_at desc nulls last,lower(title),id) from page p),'[]'::jsonb)) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_certificates (
  p_company uuid,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total',(select count(*) from public.certificates where user_id = auth.uid() and company_id = p_company),
    'items',coalesce((select jsonb_agg(to_jsonb(p) order by issued_at desc,id) from (
      select ce.id, ce.code, ce.issued_at, ce.course_id, c.title as course_title,
        co.name as company_name, pr.full_name as employee_name
      from public.certificates ce join public.courses c on c.id = ce.course_id
      join public.companies co on co.id = ce.company_id join public.profiles pr on pr.id = ce.user_id
      where ce.user_id = auth.uid() and ce.company_id = p_company order by ce.issued_at desc,ce.id limit 50 offset p_offset
    ) p),'[]'::jsonb)) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_certificates"(uuid, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_completion (
  p_company uuid
)
  RETURNS TABLE (
    user_id   uuid,
    full_name text,
    email     text,
    dept      text,
    job_title text,
    pct       numeric
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id()), false) then
    raise exception 'Forbidden';
  end if;
  return query
  select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title,
    round(100.0 * count(l.id) filter (where lp.status = 'completed') / nullif(count(l.id), 0), 1)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  left join public.courses c on public.course_company_allowed(c.id, cm.company_id)
  left join public.modules m on m.course_id = c.id
  left join public.lessons l on l.module_id = m.id
  left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
    and lp.company_id = cm.company_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  group by cm.user_id, p.id, cm.dept, cm.job_title
  order by p.full_name limit 50;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_completion"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_lessons (
  p_company uuid,
  p_course  uuid,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if not public.employee_can_access_course(p_course) then raise exception 'Course unavailable'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total', (select count(*) from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course),
    'items', coalesce((select jsonb_agg(to_jsonb(page) order by module_position, module_id, position, id) from (
      select l.id, l.title, l.kind, l.video_id, m.id as module_id, m.title as module_title,
        m.position as module_position, l.position, coalesce(lp.status,'not_started') as status,
        greatest(coalesce(lp.position_sec,0),0) as position_sec
      from public.modules m join public.lessons l on l.module_id = m.id
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
      where m.course_id = p_course order by m.position, m.id, l.position, l.id limit 50 offset p_offset
    ) page),'[]'::jsonb)) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_progress_valid (
  p_lesson uuid,
  p_status text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(public.context_role() = 'funcionario', false)
    and p_status in ('in_progress', 'completed') and not exists (
      select 1 from public.lesson_progress lp where lp.user_id = auth.uid()
        and lp.company_id = public.own_company_id() and lp.lesson_id = p_lesson
        and lp.status = 'completed' and p_status <> 'completed')
$function$;

REVOKE ALL ON FUNCTION "public"."employee_progress_valid"(uuid, text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_ranking (
  p_company uuid
)
  RETURNS TABLE (
    user_id   uuid,
    full_name text,
    dept      text,
    points    bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  return query select cm.user_id,p.full_name,cm.dept,
    coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id where lp.user_id = cm.user_id and lp.company_id = p_company and lp.status = 'completed'),0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id where d.user_id = cm.user_id and d.company_id = p_company),0)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario' order by 4 desc,lower(p.full_name),cm.user_id limit 3;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_ranking"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_summary (
  p_company uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  with course_stats as (
    select c.id, count(l.id) as total, count(l.id) filter(where lp.status = 'completed') as done
    from public.courses c left join public.modules m on m.course_id = c.id
    left join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
    where public.employee_can_access_course(c.id) group by c.id
  ), days as (
    select generate_series((now() at time zone 'America/Sao_Paulo')::date - 6,
      (now() at time zone 'America/Sao_Paulo')::date, interval '1 day')::date as day
  ), activity as (
    select d.day, exists(select 1 from public.lesson_progress lp where lp.user_id = auth.uid() and lp.company_id = p_company
      and lp.updated_at >= (d.day::timestamp at time zone 'America/Sao_Paulo')
      and lp.updated_at < ((d.day + 1)::timestamp at time zone 'America/Sao_Paulo') and lp.updated_at <= now()) as active
    from days d
  ) select jsonb_build_object(
    'course_count', (select count(*) from course_stats),
    'completed_course_count', (select count(*) from course_stats where total > 0 and done = total),
    'certificate_count', (select count(*) from public.certificates where user_id = auth.uid() and company_id = p_company),
    'balance', coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = auth.uid() and lp.company_id = p_company and lp.status = 'completed'),0)
      - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id
        where d.user_id = auth.uid() and d.company_id = p_company),0),
    'department', (select dept from public.company_memberships where user_id = auth.uid() and company_id = p_company and role = 'funcionario'),
    'activity', (select jsonb_agg(to_jsonb(a) order by day) from activity a)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_summary"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_activity_report (
  p_from date,
  p_to   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb; start_at timestamptz; end_at timestamptz;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 365 then
    raise exception 'Invalid period';
  end if;
  start_at := p_from::timestamp at time zone 'America/Sao_Paulo';
  end_at := (p_to + 1)::timestamp at time zone 'America/Sao_Paulo';
  with activity as (
    select lp.* from public.lesson_progress lp
    where lp.updated_at >= start_at and lp.updated_at < end_at
  ), months as (
    select generate_series(date_trunc('month', p_from::timestamp),
      date_trunc('month', p_to::timestamp), interval '1 month')::date as month
  ), engagement as (
    select m.month, count(distinct a.user_id) as active_users
    from months m left join activity a on
      date_trunc('month', a.updated_at at time zone 'America/Sao_Paulo')::date = m.month
    group by m.month
  ), popular as (
    select c.id as course_id, c.title, c.kind, count(*) as completions
    from activity a join public.lessons l on l.id = a.lesson_id
    join public.modules m on m.id = l.module_id join public.courses c on c.id = m.course_id
    where a.status = 'completed'
    group by c.id order by completions desc, c.id limit 10
  )
  select jsonb_build_object(
    'engagement', (select jsonb_agg(to_jsonb(e) order by month) from engagement e),
    'popular_content', coalesce((select jsonb_agg(to_jsonb(p) order by completions desc, course_id)
      from popular p), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_activity_report"(date, date) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_companies (
  p_search text    DEFAULT ''::text,
  p_active boolean DEFAULT NULL::boolean,
  p_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  with matching as (
    select c.* from public.companies c
    where strpos(lower(c.name), lower(trim(coalesce(p_search, '')))) > 0
  ), page as (
    select c.*, (select count(*) from public.company_memberships cm
      where cm.company_id = c.id and cm.role = 'funcionario') as employee_count
    from matching c where p_active is null or c.active = p_active
    order by lower(c.name), c.id limit 50 offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(p) order by lower(name), id) from page p), '[]'::jsonb),
    'active_count', (select count(*) from matching where active),
    'inactive_count', (select count(*) from matching where not active)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_companies"(text, boolean, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_completion (
  p_offset integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select coalesce(jsonb_agg(to_jsonb(page) order by pct desc nulls last, company, company_id), '[]'::jsonb)
  into result from (
    select c.id as company_id, c.name as company, r.pct
    from public.companies c left join public.completion_by_company r on r.company_id = c.id
    order by r.pct desc nulls last, c.name, c.id
    limit 50 offset greatest(coalesce(p_offset, 0), 0)
  ) page;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_completion"(integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_course_audience (
  p_course uuid
)
  RETURNS TABLE (
    all_companies boolean,
    company_ids   uuid[]
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if not exists (select 1 from public.courses where courses.id = p_course) then
    raise exception 'Course unavailable';
  end if;
  return query select c.all_companies,
    array(select a.company_id from public.assignments a
      where a.course_id = p_course and a.released order by a.company_id)
    from public.courses c where c.id = p_course;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_course_audience"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_course_lessons (
  p_course uuid,
  p_offset integer DEFAULT 0
)
  RETURNS TABLE (
    id           uuid,
    title        text,
    kind         text,
    video_id     text,
    module_title text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid page'; end if;
  if not exists (select 1 from public.courses where courses.id = p_course) then
    raise exception 'Course unavailable';
  end if;
  return query select l.id, l.title, l.kind, l.video_id, m.title
    from public.modules m join public.lessons l on l.module_id = m.id
    where m.course_id = p_course
    order by m.position, m.id, l.position, l.id limit 50 offset p_offset;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_dashboard()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  with clock as (
    select (now() at time zone 'America/Sao_Paulo')::date as today
  ), months as (
    select generate_series(date_trunc('month', today) - interval '5 months',
      date_trunc('month', today), interval '1 month')::date as month from clock
  ), opportunities as (
    select lp.status
    from public.company_memberships cm
    join public.courses c on public.course_company_allowed(c.id, cm.company_id)
    join public.modules m on m.course_id = c.id
    join public.lessons l on l.module_id = m.id
    left join public.lesson_progress lp on lp.user_id = cm.user_id
      and lp.company_id = cm.company_id and lp.lesson_id = l.id
    where cm.role = 'funcionario'
  ), growth as (
    select month,
      (select count(*) from public.companies c where c.created_at <
        ((month + interval '1 month') at time zone 'America/Sao_Paulo')) as companies,
      (select count(*) from public.profiles p join auth.users u on u.id = p.id
        where u.created_at < ((month + interval '1 month') at time zone 'America/Sao_Paulo')) as users
    from months
  ), recent_companies as (
    select c.* from public.companies c order by c.created_at desc, c.id limit 10
  ), recent_progress as (
    select lp.* from public.lesson_progress lp
    order by lp.updated_at desc, lp.company_id, lp.user_id, lp.lesson_id limit 10
  ), recent as (
    select 'company:' || c.id::text as id, 'company'::text as kind,
      c.name as name, null::text as title, c.created_at as occurred_at
    from recent_companies c
    union all
    select 'progress:' || lp.company_id::text || ':' || lp.user_id::text || ':' || lp.lesson_id::text,
      'progress', p.full_name, l.title, lp.updated_at
    from recent_progress lp join public.profiles p on p.id = lp.user_id
    join public.lessons l on l.id = lp.lesson_id
  ), latest as (
    select * from recent order by occurred_at desc, id limit 10
  )
  select jsonb_build_object(
    'company_count', (select count(*) from public.companies),
    'new_company_count', (select count(*) from public.companies c, clock
      where c.created_at >= (date_trunc('month', today)::timestamp at time zone 'America/Sao_Paulo')),
    'user_count', (select count(*) from public.profiles),
    'active_user_count', (select count(distinct user_id) from public.lesson_progress
      where updated_at >= now() - interval '30 days' and updated_at <= now()),
    'completion_pct', (select round(100.0 * count(*) filter (where status = 'completed')
      / nullif(count(*), 0), 1) from opportunities),
    'growth', (select jsonb_agg(to_jsonb(g) order by month) from growth g),
    'activities', coalesce((select jsonb_agg(to_jsonb(a) order by occurred_at desc, id)
      from latest a), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_dashboard"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.gestor_managers (
  p_company uuid    DEFAULT NULL::uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS TABLE (
    id        uuid,
    full_name text,
    email     text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then
    raise exception 'Invalid page';
  end if;
  return query select p.id, p.full_name, p.email from public.profiles p
    where (case when p_company is null then exists (
      select 1 from public.platform_gestors g where g.user_id = p.id)
    else exists (select 1 from public.company_memberships m
      where m.user_id = p.id and m.company_id = p_company and m.role = 'empresa') end)
    and (strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0 or
      strpos(lower(p.email), lower(coalesce(p_search, ''))) > 0)
    order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

REVOKE ALL ON FUNCTION "public"."gestor_managers"(uuid, text, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.is_gestor()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $function$
  select public.context_role() = 'gestor'
$function$;

REVOKE ALL ON FUNCTION "public"."is_gestor"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.issue_employee_certificate (
  p_user    uuid,
  p_session uuid,
  p_company uuid,
  p_course  uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid; prefix text; code_value text;
begin
  perform pg_advisory_xact_lock(hashtext(p_user::text || p_company::text || p_course::text));
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id = sc.user_id and cm.company_id = sc.company_id and cm.role = sc.role
    join public.companies co on co.id = cm.company_id and co.active
    where sc.user_id = p_user and sc.session_id = p_session and sc.role = 'funcionario' and sc.company_id = p_company for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform 1 from public.courses c where c.id = p_course and c.status = 'released' and public.course_company_allowed(c.id,p_company)
    and coalesce((select company_enabled from public.assignments a where a.course_id = c.id and a.company_id = p_company),true) for share;
  if not found then raise exception 'Course unavailable'; end if;
  if not exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course)
    or exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = p_user and lp.company_id = p_company
      where m.course_id = p_course and lp.status is distinct from 'completed') then raise exception 'Course incomplete'; end if;
  select id into result from public.certificates where user_id = p_user and company_id = p_company and course_id = p_course;
  if found then return result; end if;
  select co.code_prefix into prefix from public.companies co where co.id = p_company;
  for attempt in 1..10 loop
    code_value := prefix || '-';
    for digit in 1..6 loop code_value := code_value || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ',1+floor(random()*32)::int,1); end loop;
    begin
      insert into public.certificates(user_id,company_id,course_id,code) values(p_user,p_company,p_course,code_value) returning id into result;
      return result;
    exception when unique_violation then null;
    end;
  end loop;
  raise exception 'Certificate code unavailable';
end $function$;

REVOKE ALL ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.move_content_item (
  p_kind      text,
  p_id        uuid,
  p_direction integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare parent uuid; ids uuid[]; current_index int; target_index int; other uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_kind is null or p_kind not in ('module','lesson') or p_direction is null or p_direction not in (-1,1) then raise exception 'Invalid move'; end if;
  if p_kind='module' then
    select course_id into parent from public.modules where id=p_id;
    if not found then raise exception 'Module unavailable'; end if;
    perform 1 from public.courses where id=parent for update;
    select array_agg(id order by position,id) into ids from public.modules where course_id=parent;
  else
    select module_id into parent from public.lessons where id=p_id;
    if not found then raise exception 'Lesson unavailable'; end if;
    perform 1 from public.modules where id=parent for update;
    select array_agg(id order by position,id) into ids from public.lessons where module_id=parent;
  end if;
  current_index:=array_position(ids,p_id);
  if current_index is null then raise exception 'Content unavailable'; end if;
  target_index:=current_index+p_direction;
  if target_index<1 or target_index>cardinality(ids) then return; end if;
  other:=ids[target_index]; ids[target_index]:=p_id; ids[current_index]:=other;
  if p_kind='module' then
    update public.modules m set position=s.ordinality::int from unnest(ids) with ordinality s(id,ordinality) where m.id=s.id;
  else
    update public.lessons l set position=s.ordinality::int from unnest(ids) with ordinality s(id,ordinality) where l.id=s.id;
  end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."move_content_item"(text, uuid, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.own_company_id()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$function$;

REVOKE ALL ON FUNCTION "public"."own_company_id"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.pending_invites()
  RETURNS TABLE (
    email      text,
    role       text,
    company_id uuid,
    expires_at timestamp with time zone,
    full_name  text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
  order by mi.created_at desc limit 50
$function$;

REVOKE ALL ON FUNCTION "public"."pending_invites"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.pending_invites_page (
  p_role    text DEFAULT NULL::text,
  p_company uuid DEFAULT NULL::uuid
)
  RETURNS TABLE (
    email        text,
    role         text,
    company_id   uuid,
    expires_at   timestamp with time zone,
    full_name    text,
    company_name text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name, c.name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  left join public.companies c on c.id = mi.company_id
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
    and (p_role is null or mi.role = p_role)
    and (p_company is null or mi.company_id = p_company)
  order by mi.created_at desc, mi.id limit 50
$function$;

REVOKE ALL ON FUNCTION "public"."pending_invites_page"(text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.publish_video_trail (
  p_title          text,
  p_description    text,
  p_module_title   text,
  p_video_id       text,
  p_all_companies  boolean DEFAULT true,
  p_company_ids    uuid[]  DEFAULT '{}'::uuid[],
  p_cover_key      text    DEFAULT NULL::text,
  p_responsible_id uuid    DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare course_id uuid; module_id uuid;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 or p_module_title is null or
    length(trim(p_module_title)) not between 1 and 200 or
    p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    raise exception 'Invalid trail';
  end if;
  if p_cover_key is not null and (length(p_cover_key) > 200 or
    p_cover_key !~ '^covers/[A-Za-z0-9_-]{1,120}\.webp$') then
    raise exception 'Invalid cover';
  end if;
  if p_responsible_id is not null and not exists (
    select 1 from public.platform_gestors g where g.user_id = p_responsible_id) then
    raise exception 'Invalid responsible';
  end if;
  insert into public.courses(title, kind, description, status, created_by,
    all_companies, cover_key, responsible_id)
    values (trim(p_title), 'course', coalesce(p_description, ''), 'released',
      auth.uid(), true, p_cover_key, p_responsible_id)
    returning id into course_id;
  perform public.set_course_audience(course_id, p_all_companies, p_company_ids);
  insert into public.modules(course_id, title, position)
    values (course_id, trim(p_module_title), 1) returning id into module_id;
  insert into public.lessons(module_id, title, kind, video_provider, video_id, position)
    values (module_id, trim(p_title), 'video', 'youtube', p_video_id, 1);
  return course_id;
end $function$;

REVOKE ALL ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.ranking (
  p_company uuid,
  p_limit   integer DEFAULT 20
)
  RETURNS TABLE (
    full_name text,
    dept      text,
    points    bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor() or (public.context_role() in ('empresa', 'funcionario')
    and p_company = public.own_company_id()), false) then raise exception 'Forbidden'; end if;
  return query select p.full_name, cm.dept,
    (coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = p.id and lp.company_id = p_company and lp.status = 'completed'), 0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id
      where d.user_id = p.id and d.company_id = p_company), 0))::bigint
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  order by 3 desc, lower(p.full_name), p.id limit least(greatest(coalesce(p_limit,20),1),100);
end $function$;

REVOKE ALL ON FUNCTION "public"."ranking"(uuid, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.redeem_employee_reward (
  p_company uuid,
  p_reward  uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform public.redeem_reward(p_reward);
end $function$;

REVOKE ALL ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.redeem_reward (
  p_reward uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare cost int; earned int; spent int; cid uuid := public.own_company_id();
begin
  if public.context_role() <> 'funcionario' or cid is null then
    raise exception 'Employee context required';
  end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text || cid::text));
  select points_cost into cost from public.rewards where id = p_reward and active;
  if not found then raise exception 'Reward unavailable'; end if;
  select coalesce(sum(l.points), 0) into earned from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id
    where lp.user_id = auth.uid() and lp.company_id = cid and lp.status = 'completed';
  select coalesce(sum(r.points_cost), 0) into spent from public.redemptions d
    join public.rewards r on r.id = d.reward_id
    where d.user_id = auth.uid() and d.company_id = cid;
  if earned - spent < cost then raise exception 'Insufficient points'; end if;
  insert into public.redemptions(user_id, company_id, reward_id)
  values (auth.uid(), cid, p_reward);
end $function$;

REVOKE ALL ON FUNCTION "public"."redeem_reward"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.revoke_gestor_access (
  p_user    uuid,
  p_company uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_company is null then
    -- Serialize removals and grant writes; two simultaneous removals cannot
    -- each observe the other gestor and leave the platform without one.
    lock table public.platform_gestors in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.platform_gestors where user_id = p_user) then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.platform_gestors) <= 1 then
      raise exception 'Last platform gestor';
    end if;
    delete from public.platform_gestors where user_id = p_user;
    delete from public.session_contexts where user_id = p_user and role = 'gestor';
  else
    -- Also serialize against platform revocations while checking the caller.
    lock table public.platform_gestors in share mode;
    lock table public.company_memberships in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa') then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.company_memberships
      where company_id = p_company and role = 'empresa') <= 1 then
      raise exception 'Last company gestor';
    end if;
    delete from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa';
    delete from public.session_contexts
      where user_id = p_user and company_id = p_company and role = 'empresa';
  end if;
  delete from public.membership_invites where lower(email) = (
    select lower(email) from public.profiles where id = p_user)
    and role = case when p_company is null then 'gestor' else 'empresa' end
    and company_id is not distinct from p_company;
  -- Identity, employee memberships, other companies and course authorship stay.
end $function$;

REVOKE ALL ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.save_content_lesson (
  p_module uuid,
  p_title  text,
  p_kind   text,
  p_data   jsonb,
  p_lesson uuid  DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid; keys text[]; k text; q jsonb; frame int;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or p_kind is null or
    p_kind not in ('video','audio','pdf','reading','quiz','animation') or p_data is null or
    jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text)>500000 or
    length(coalesce(p_data->>'body',''))>100000 then raise exception 'Invalid lesson'; end if;
  perform 1 from public.modules where id=p_module for update;
  if not found then raise exception 'Module unavailable'; end if;
  if p_lesson is not null and not exists(select 1 from public.lessons where id=p_lesson and module_id=p_module and kind=p_kind) then
    raise exception 'Lesson unavailable or type changed'; end if;
  keys := array(select jsonb_array_elements_text(coalesce(p_data->'image_keys','[]')));
  k := nullif(p_data->>'file_key','');
  frame := coalesce((p_data->>'frame_ms')::int,1000);
  if frame not between 100 and 10000 or cardinality(keys)>100 then raise exception 'Invalid animation'; end if;
  if k is not null and k !~ '^lessons/[a-f0-9-]{36}\.(pdf|mp3|gif|png|jpg|webp)$' then raise exception 'Invalid file'; end if;
  if exists(select 1 from unnest(keys) key where key !~ '^lessons/[a-f0-9-]{36}\.(png|jpg|webp)$') then raise exception 'Invalid frame'; end if;
  if (p_kind='video' and coalesce(p_data->>'video_id','') !~ '^[A-Za-z0-9_-]{11}$') or
     (p_kind='audio' and coalesce(k,'') !~ '\.mp3$') or
     (p_kind='pdf' and coalesce(k,'') !~ '\.pdf$') or
     (p_kind='reading' and length(trim(coalesce(p_data->>'body',''))) not between 1 and 100000) or
     (p_kind='animation' and not ((coalesce(k,'') ~ '\.(gif|png|jpg|webp)$' and cardinality(keys)=0) or (k is null and cardinality(keys) between 2 and 100))) then
    raise exception 'Missing content'; end if;
  if p_kind='quiz' then
    if jsonb_typeof(p_data->'questions') is distinct from 'array' then raise exception 'Invalid quiz'; end if;
    if jsonb_array_length(p_data->'questions') not between 1 and 50 then raise exception 'Invalid quiz'; end if;
    for q in select jsonb_array_elements(p_data->'questions') loop
      if length(trim(coalesce(q->>'question',''))) not between 1 and 1000 or jsonb_typeof(q->'options') is distinct from 'array' then raise exception 'Invalid question'; end if;
      if jsonb_array_length(q->'options') not between 2 and 6 or (q->>'answer')::int not between 0 and jsonb_array_length(q->'options')-1 or q->>'answer' is null or
        exists(select 1 from jsonb_array_elements(q->'options') o where jsonb_typeof(o)<>'string' or length(trim(o #>> '{}')) not between 1 and 500) then raise exception 'Invalid answers'; end if;
    end loop;
  end if;
  if p_lesson is null then
    insert into public.lessons(module_id,title,kind,position) select p_module,trim(p_title),p_kind,coalesce(max(position),0)+1
      from public.lessons where module_id=p_module returning id into result;
  else result := p_lesson; end if;
  update public.lessons set title=trim(p_title), video_id=case when p_kind='video' then p_data->>'video_id' end,
    file_key=case when p_kind in ('audio','pdf','animation') then k end,
    body=coalesce(p_data->>'body',''),
    quiz_json=case when p_kind='quiz' then p_data->'questions' end,
    image_keys=case when p_kind='animation' then keys else '{}' end, frame_ms=frame where id=result;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.save_content_module (
  p_course uuid,
  p_title  text,
  p_module uuid DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then raise exception 'Invalid title'; end if;
  perform 1 from public.courses where id=p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_module is null then
    insert into public.modules(course_id,title,position) select p_course,trim(p_title),coalesce(max(position),0)+1
      from public.modules where course_id=p_course returning id into result;
  else
    update public.modules set title=trim(p_title) where id=p_module and course_id=p_course returning id into result;
    if not found then raise exception 'Module unavailable'; end if;
  end if;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."save_content_module"(uuid, text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.save_employee_progress (
  p_company   uuid,
  p_lesson    uuid,
  p_position  integer,
  p_completed boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  if p_position is null or p_position < 0 or p_completed is null then raise exception 'Invalid progress'; end if;
  perform 1 from public.lessons l join public.modules m on m.id=l.module_id join public.courses c on c.id=m.course_id
    where l.id=p_lesson and public.employee_can_access_course(m.course_id) and case l.kind
      when 'video' then l.video_id is not null
      when 'audio' then l.file_key is not null
      when 'pdf' then l.file_key is not null
      when 'reading' then length(trim(l.body))>0
      when 'animation' then l.file_key is not null or cardinality(l.image_keys)>=2
      when 'quiz' then case when jsonb_typeof(l.quiz_json)='array' then jsonb_array_length(l.quiz_json)>0 else false end
      else false end for share of c;
  if not found then raise exception 'Lesson unavailable'; end if;
  -- All formats use the same company-scoped progress; completion is client-reported MVP.
  insert into public.lesson_progress(user_id,company_id,lesson_id,status,position_sec)
    values(auth.uid(),p_company,p_lesson,case when p_completed then 'completed' else 'in_progress' end,p_position)
    on conflict(user_id,company_id,lesson_id) do update set
      status=case when lesson_progress.status='completed' or p_completed then 'completed' else 'in_progress' end,
      position_sec=excluded.position_sec,updated_at=now();
end $function$;

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.select_context (
  p_role       text,
  p_company_id uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if auth.uid() is null or sid is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.available_contexts() ac
    where ac.role = p_role and ac.company_id is not distinct from p_company_id) then
    raise exception 'Context unavailable';
  end if;
  insert into public.session_contexts(session_id, user_id, role, company_id)
  values (sid, auth.uid(), p_role, p_company_id)
  on conflict (session_id) do update set role = excluded.role,
    company_id = excluded.company_id, updated_at = now()
  where session_contexts.user_id = excluded.user_id;
  if not found then raise exception 'Session mismatch'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."select_context"(text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.selected_context()
  RETURNS TABLE (
    role       text,
    company_id uuid
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select sc.role, sc.company_id from public.session_contexts sc
  where sc.user_id = (select auth.uid())
    and sc.session_id = nullif(auth.jwt()->>'session_id', '')::uuid
    and sc.role = public.context_role()
  limit 1
$function$;

REVOKE ALL ON FUNCTION "public"."selected_context"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.set_company_active (
  p_company uuid,
  p_active  boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_active is null then raise exception 'Invalid company'; end if;
  update public.companies set active = p_active where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
  -- Pauses retain grants, progress and the selected contexts for reactivation.
end $function$;

REVOKE ALL ON FUNCTION "public"."set_company_active"(uuid, boolean) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.set_course_audience (
  p_course        uuid,
  p_all_companies boolean,
  p_company_ids   uuid[]  DEFAULT '{}'::uuid[]
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_all_companies is null or p_company_ids is null or
    (not p_all_companies and cardinality(p_company_ids) = 0) or
    exists (select 1 from unnest(p_company_ids) as ids(company_id)
      where ids.company_id is null or not exists (
        select 1 from public.companies c where c.id = ids.company_id)) then
    raise exception 'Invalid audience';
  end if;
  -- Serialize audience replacement with company changes on the same trail.
  perform 1 from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  update public.courses set all_companies = p_all_companies where id = p_course;
  if not p_all_companies then
    update public.assignments set released = false where course_id = p_course;
    insert into public.assignments(course_id, company_id, released)
      select p_course, id, true from (select distinct unnest(p_company_ids) as id) ids
      on conflict (course_id, company_id) do update set released = true;
  end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.set_course_company_enabled (
  p_course  uuid,
  p_enabled boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare cid uuid := public.own_company_id();
begin
  if public.context_role() is distinct from 'empresa' or cid is null then
    raise exception 'Forbidden';
  end if;
  if p_enabled is null then raise exception 'Invalid state'; end if;
  perform 1 from public.courses where id = p_course for update;
  if not found or not public.course_company_allowed(p_course, cid) then
    raise exception 'Course unavailable';
  end if;
  insert into public.assignments(course_id, company_id, released, company_enabled)
    values (p_course, cid, false, p_enabled)
    on conflict (course_id, company_id) do update set company_enabled = excluded.company_enabled;
end $function$;

REVOKE ALL ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.set_course_platform_enabled (
  p_course  uuid,
  p_enabled boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_enabled is null then raise exception 'Invalid state'; end if;
  update public.courses set status = case when p_enabled then 'released' else 'paused' end
    where id = p_course;
  if not found then raise exception 'Course unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.update_company (
  p_company uuid,
  p_fields  jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or
    length(trim(coalesce(p_fields->>'name', ''))) not between 1 and 200 or
    exists (select 1 from jsonb_each_text(p_fields) f where length(f.value) > 500) or
    (coalesce(p_fields->>'email', '') <> '' and
      p_fields->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'Invalid company';
  end if;
  update public.companies set name = trim(p_fields->>'name'),
    cnpj = nullif(trim(p_fields->>'cnpj'), ''),
    responsible = nullif(trim(p_fields->>'responsible'), ''),
    email = nullif(trim(p_fields->>'email'), ''),
    phone = nullif(trim(p_fields->>'phone'), ''),
    address = nullif(trim(p_fields->>'address'), ''),
    city = nullif(trim(p_fields->>'city'), ''),
    state = nullif(upper(trim(p_fields->>'state')), ''),
    field = nullif(trim(p_fields->>'field'), '')
    where id = p_company;
  if not found then raise exception 'Company unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."update_company"(uuid, jsonb) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.update_course_lesson (
  p_lesson       uuid,
  p_module_title text,
  p_title        text,
  p_video_id     text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare existing public.lessons;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.lessons where id = p_lesson for update;
  if not found then raise exception 'Lesson unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    p_module_title is null or length(trim(p_module_title)) not between 1 and 200 or
    (existing.kind = 'video' and (p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$')) or
    (existing.kind <> 'video' and p_video_id is not null) then
    raise exception 'Invalid lesson';
  end if;
  update public.modules set title = trim(p_module_title) where id = existing.module_id;
  update public.lessons set title = trim(p_title),
    video_id = case when kind = 'video' then p_video_id else video_id end
    where id = p_lesson;
end $function$;

REVOKE ALL ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.update_course_metadata (
  p_course         uuid,
  p_title          text,
  p_description    text,
  p_cover_key      text,
  p_responsible_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare existing public.courses;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 then raise exception 'Invalid course'; end if;
  if p_cover_key is distinct from existing.cover_key and p_cover_key is not null and
    (length(p_cover_key) > 200 or p_cover_key !~ '^covers/[A-Za-z0-9_-]{1,120}\.webp$') then
    raise exception 'Invalid cover';
  end if;
  if p_responsible_id is distinct from existing.responsible_id and
    p_responsible_id is not null and not exists (
      select 1 from public.platform_gestors where user_id = p_responsible_id) then
    raise exception 'Invalid responsible';
  end if;
  update public.courses set title = trim(p_title), description = coalesce(p_description, ''),
    cover_key = p_cover_key, responsible_id = p_responsible_id where id = p_course;
  -- Never replace rows or alter status, audience, company preferences or points.
end $function$;

REVOKE ALL ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.update_own_profile (
  p_name       text,
  p_phone      text,
  p_birth_date date,
  p_address    text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 200 or
    length(coalesce(p_phone, '')) > 50 or length(coalesce(p_address, '')) > 500 or
    p_birth_date > current_date then raise exception 'Invalid profile'; end if;
  update public.profiles set full_name = trim(p_name),
    phone = nullif(trim(p_phone), ''), birth_date = p_birth_date,
    address = nullif(trim(p_address), '') where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text) FROM PUBLIC, "anon", "service_role";

ALTER TABLE "public"."assignments"
  ADD CONSTRAINT "assignments_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE "public"."certificates"
  ADD CONSTRAINT "certificates_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id);

ALTER TABLE "public"."company_memberships"
  ADD CONSTRAINT "company_memberships_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE "public"."assignments"
  ADD CONSTRAINT "assignments_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;

ALTER TABLE "public"."certificates"
  ADD CONSTRAINT "certificates_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "lesson_progress_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id);

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "progress_nonnegative_position" CHECK ((position_sec >= 0)) NOT VALID;

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "lesson_progress_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES public.lessons(id) ON DELETE CASCADE;

ALTER TABLE "public"."membership_invites"
  ADD CONSTRAINT "membership_invites_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE "public"."modules"
  ADD CONSTRAINT "modules_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;

ALTER TABLE "public"."lessons"
  ADD CONSTRAINT "lessons_module_id_fkey" FOREIGN KEY (module_id) REFERENCES public.modules(id) ON DELETE CASCADE;

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "public"."certificates"
  ADD CONSTRAINT "certificates_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."company_memberships"
  ADD CONSTRAINT "company_memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."courses"
  ADD CONSTRAINT "courses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.profiles(id);

ALTER TABLE "public"."courses"
  ADD CONSTRAINT "courses_responsible_id_fkey" FOREIGN KEY (responsible_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE "public"."fcm_tokens"
  ADD CONSTRAINT "fcm_tokens_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "lesson_progress_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."membership_invites"
  ADD CONSTRAINT "membership_invites_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE "public"."platform_gestors"
  ADD CONSTRAINT "platform_gestors_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."redemptions"
  ADD CONSTRAINT "redemptions_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id);

ALTER TABLE "public"."redemptions"
  ADD CONSTRAINT "redemptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE "public"."redemptions"
  ADD CONSTRAINT "redemptions_reward_id_fkey" FOREIGN KEY (reward_id) REFERENCES public.rewards(id);

ALTER TABLE "public"."session_contexts"
  ADD CONSTRAINT "session_contexts_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE "public"."session_contexts"
  ADD CONSTRAINT "session_contexts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

CREATE VIEW "public"."completion_by_company" AS  SELECT co.id AS company_id,
    co.name AS company,
    round(((100.0 * (count(*) FILTER (WHERE (lp.status = 'completed'::text)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct
   FROM (((((public.companies co
     JOIN public.company_memberships cm ON (((cm.company_id = co.id) AND (cm.role = 'funcionario'::text))))
     JOIN public.courses c ON ((c.all_companies OR (EXISTS ( SELECT 1
           FROM public.assignments a
          WHERE ((a.course_id = c.id) AND (a.company_id = co.id) AND a.released))))))
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     LEFT JOIN public.lesson_progress lp ON (((lp.lesson_id = l.id) AND (lp.user_id = cm.user_id) AND (lp.company_id = co.id))))
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (co.id = public.own_company_id())))
  GROUP BY co.id;

REVOKE ALL ON TABLE "public"."completion_by_company" FROM "anon";

CREATE VIEW "public"."completion_by_dept" AS  SELECT cm.company_id,
    cm.dept AS department,
    round(((100.0 * (count(*) FILTER (WHERE (lp.status = 'completed'::text)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct
   FROM ((((public.company_memberships cm
     JOIN public.courses c ON ((c.all_companies OR (EXISTS ( SELECT 1
           FROM public.assignments a
          WHERE ((a.course_id = c.id) AND (a.company_id = cm.company_id) AND a.released))))))
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     LEFT JOIN public.lesson_progress lp ON (((lp.lesson_id = l.id) AND (lp.user_id = cm.user_id) AND (lp.company_id = cm.company_id))))
  WHERE ((cm.role = 'funcionario'::text) AND (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (cm.company_id = public.own_company_id()))))
  GROUP BY cm.company_id, cm.dept;

REVOKE ALL ON TABLE "public"."completion_by_dept" FROM "anon";

CREATE VIEW "public"."engagement_monthly" AS  SELECT company_id,
    (date_trunc('month'::text, updated_at))::date AS month,
    count(DISTINCT user_id) AS active_users,
    count(*) AS events
   FROM public.lesson_progress
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (company_id = public.own_company_id())))
  GROUP BY company_id, ((date_trunc('month'::text, updated_at))::date);

REVOKE ALL ON TABLE "public"."engagement_monthly" FROM "anon";

CREATE VIEW "public"."popular_content" AS  SELECT lp.company_id,
    c.title AS course,
    count(*) FILTER (WHERE (lp.status = 'completed'::text)) AS completions
   FROM (((public.courses c
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     JOIN public.lesson_progress lp ON ((lp.lesson_id = l.id)))
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (lp.company_id = public.own_company_id())))
  GROUP BY lp.company_id, c.title;

REVOKE ALL ON TABLE "public"."popular_content" FROM "anon";

CREATE INDEX company_memberships_company_role_idx ON public.company_memberships USING btree (company_id, ROLE);

CREATE INDEX lesson_progress_updated_at_idx ON public.lesson_progress USING btree (updated_at);

CREATE UNIQUE INDEX membership_invites_unique_pending ON public.membership_invites
  USING btree (lower(email), ROLE, COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE UNIQUE INDEX profiles_email_ci ON public.profiles USING btree (lower(email));

CREATE INDEX session_contexts_user_id_idx ON public.session_contexts USING btree (user_id);

CREATE POLICY "assignments_select" ON "public"."assignments"
  FOR SELECT
  TO PUBLIC
  USING ((public.is_gestor() OR (company_id = public.own_company_id())));

CREATE POLICY "assignments_write" ON "public"."assignments"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "certificates_select" ON "public"."certificates"
  FOR SELECT
  TO "authenticated"
  USING
    ((public.is_gestor() OR ((company_id = public.own_company_id()) AND ((public.context_role() = 'empresa'::text) OR ((public.context_role() = 'funcionario'::text) AND (user_id =
    auth.uid()))))));

CREATE POLICY "companies_delete" ON "public"."companies"
  FOR DELETE
  TO PUBLIC
  USING (public.is_gestor());

CREATE POLICY "companies_insert" ON "public"."companies"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (public.is_gestor());

CREATE POLICY "companies_select" ON "public"."companies"
  FOR SELECT
  TO PUBLIC
  USING ((public.is_gestor() OR (id = public.own_company_id())));

CREATE POLICY "companies_update" ON "public"."companies"
  FOR UPDATE
  TO "authenticated"
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "company_memberships_select" ON "public"."company_memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (company_id = public.own_company_id()))));

CREATE POLICY "courses_select" ON "public"."courses"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR public.employee_can_access_course(id)));

CREATE POLICY "courses_write" ON "public"."courses"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "fcm_tokens_all" ON "public"."fcm_tokens"
  FOR ALL
  TO "authenticated"
  USING ((user_id = auth.uid()))
  WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "progress_delete" ON "public"."lesson_progress"
  FOR DELETE
  TO "authenticated"
  USING (public.is_gestor());

CREATE POLICY "progress_insert" ON "public"."lesson_progress"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "progress_select" ON "public"."lesson_progress"
  FOR SELECT
  TO "authenticated"
  USING
    ((public.is_gestor() OR ((company_id = public.own_company_id()) AND ((public.context_role() = 'empresa'::text) OR ((public.context_role() = 'funcionario'::text) AND (user_id =
    auth.uid()))))));

CREATE POLICY "progress_update" ON "public"."lesson_progress"
  FOR UPDATE
  TO "authenticated"
  USING (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))))
  WITH CHECK (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "progress_valid_insert" ON "public"."lesson_progress"
  AS RESTRICTIVE
  FOR INSERT
  TO "authenticated"
  WITH CHECK (public.employee_progress_valid(lesson_id, status));

CREATE POLICY "progress_valid_update" ON "public"."lesson_progress"
  AS RESTRICTIVE
  FOR UPDATE
  TO "authenticated"
  WITH CHECK (public.employee_progress_valid(lesson_id, status));

CREATE POLICY "lessons_select" ON "public"."lessons"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR (EXISTS ( SELECT 1
   FROM public.modules m
  WHERE ((m.id = lessons.module_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "lessons_write" ON "public"."lessons"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "modules_select" ON "public"."modules"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR public.employee_can_access_course(course_id)));

CREATE POLICY "modules_write" ON "public"."modules"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "platform_gestors_select" ON "public"."platform_gestors"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR public.is_gestor()));

CREATE POLICY "profiles_select" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (((id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (EXISTS ( SELECT 1
   FROM public.company_memberships cm
  WHERE ((cm.user_id = profiles.id) AND (cm.company_id = public.own_company_id())))))));

CREATE POLICY "profiles_update" ON "public"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING ((id = auth.uid()))
  WITH CHECK ((id = auth.uid()));

CREATE POLICY "redemptions_select" ON "public"."redemptions"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR ((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()))));

CREATE POLICY "rewards_select" ON "public"."rewards"
  FOR SELECT
  TO "authenticated"
  USING ((active AND (public.is_gestor() OR (public.context_role() = 'funcionario'::text))));

CREATE POLICY "rewards_write" ON "public"."rewards"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

CREATE POLICY "storage_public_delete" ON "storage"."objects"
  FOR DELETE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND public.is_gestor()));

CREATE POLICY "storage_public_read" ON "storage"."objects"
  FOR SELECT
  TO PUBLIC
  USING ((bucket_id = 'educador-public'::text));

CREATE POLICY "storage_public_update" ON "storage"."objects"
  FOR UPDATE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND public.is_gestor()))
  WITH CHECK (((bucket_id = 'educador-public'::text) AND public.is_gestor()));

CREATE POLICY "storage_public_write" ON "storage"."objects"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((bucket_id = 'educador-public'::text) AND public.is_gestor()));

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."clear_context"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."clear_context"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_dashboard"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."company_dashboard"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_dashboard"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_employees"(uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."company_employees"(uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_employees"(uuid, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."content_catalog"(text, text, integer, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."content_catalog"(text, text, integer, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."content_catalog"(text, text, integer, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."context_role"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."course_company_allowed"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."course_company_allowed"(uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_content_course"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."create_content_course"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_content_course"(text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."custom_access_token_hook"(jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."custom_access_token_hook"(jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."custom_access_token_hook"(jsonb) TO "supabase_auth_admin";

GRANT EXECUTE ON FUNCTION "public"."delete_content"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."delete_content"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."delete_content"(text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_can_access_course"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_can_access_course"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_can_access_course"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_certificates"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_certificates"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_certificates"(uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_completion"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_completion"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_completion"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_progress_valid"(uuid, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_progress_valid"(uuid, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_progress_valid"(uuid, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_ranking"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_ranking"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_ranking"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_summary"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_summary"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_summary"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_activity_report"(date, date) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_activity_report"(date, date) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_activity_report"(date, date) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_companies"(text, boolean, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_companies"(text, boolean, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_companies"(text, boolean, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_completion"(integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_completion"(integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_completion"(integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_audience"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_course_audience"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_audience"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_dashboard"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_dashboard"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_dashboard"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_managers"(uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_managers"(uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_managers"(uuid, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."is_gestor"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."is_gestor"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."is_gestor"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."move_content_item"(text, uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."move_content_item"(text, uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."move_content_item"(text, uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."own_company_id"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."own_company_id"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."own_company_id"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."pending_invites"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites_page"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."pending_invites_page"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites_page"(text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."ranking"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."ranking"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."ranking"(uuid, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_reward"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."redeem_reward"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_reward"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_module"(uuid, text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_content_module"(uuid, text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_module"(uuid, text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."select_context"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."select_context"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."select_context"(text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."selected_context"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."selected_context"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."selected_context"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_company_active"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_company_active"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_company_active"(uuid, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_company"(uuid, jsonb) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_company"(uuid, jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_company"(uuid, jsonb) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text) TO "postgres";

REVOKE ALL ON TABLE "public"."assignments" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."assignments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."assignments" TO "service_role";

REVOKE ALL ON TABLE "public"."certificates" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."certificates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."certificates" TO "service_role";

REVOKE ALL ON TABLE "public"."companies" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."companies" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "service_role";

REVOKE ALL ON TABLE "public"."company_memberships" FROM "authenticated";

GRANT SELECT ON TABLE "public"."company_memberships" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."company_memberships" TO "service_role";

REVOKE ALL ON TABLE "public"."courses" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."courses" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."courses" TO "service_role";

REVOKE ALL ON TABLE "public"."fcm_tokens" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."fcm_tokens" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."fcm_tokens" TO "service_role";

REVOKE ALL ON TABLE "public"."lesson_progress" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."lesson_progress" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lesson_progress" TO "service_role";

REVOKE ALL ON TABLE "public"."lessons" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."lessons" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lessons" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."membership_invites" TO "service_role";

REVOKE ALL ON TABLE "public"."modules" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."modules" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."modules" TO "service_role";

REVOKE ALL ON TABLE "public"."platform_gestors" FROM "authenticated";

GRANT SELECT ON TABLE "public"."platform_gestors" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."platform_gestors" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("address") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("address") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("avatar_key") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("avatar_key") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("birth_date") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("birth_date") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("full_name") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("needs_password") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("needs_password") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("phone") ON TABLE "public"."profiles" FROM "authenticated";

GRANT UPDATE ("phone") ON TABLE "public"."profiles" TO "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."redemptions" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."redemptions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."redemptions" TO "service_role";

REVOKE ALL ON TABLE "public"."rewards" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."rewards" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."rewards" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."session_contexts" TO "service_role";

REVOKE ALL ON TABLE "public"."completion_by_company" FROM "authenticated";

GRANT SELECT ON TABLE "public"."completion_by_company" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_company" TO "service_role";

REVOKE ALL ON TABLE "public"."completion_by_dept" FROM "authenticated";

GRANT SELECT ON TABLE "public"."completion_by_dept" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_dept" TO "service_role";

REVOKE ALL ON TABLE "public"."engagement_monthly" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engagement_monthly" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engagement_monthly" TO "service_role";

REVOKE ALL ON TABLE "public"."popular_content" FROM "authenticated";

GRANT SELECT ON TABLE "public"."popular_content" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."popular_content" TO "service_role";
