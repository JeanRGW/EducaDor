SET local check_function_bodies = off;

ALTER TABLE "public"."assignments"
  ADD COLUMN "push_pending_at" timestamp WITH time zone;

ALTER TABLE "public"."assignments"
  ADD COLUMN "push_claimed_at" timestamp WITH time zone;

ALTER TABLE "public"."certificates"
  ADD COLUMN "push_claimed_at" timestamp WITH time zone;

ALTER TABLE "public"."courses"
  ADD COLUMN "push_pending_at" timestamp WITH time zone;

ALTER TABLE "public"."courses"
  ADD COLUMN "push_claimed_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION public.claim_push_recipients (
  p_user        uuid,
  p_session     uuid,
  p_event       text,
  p_course      uuid,
  p_company     uuid,
  p_certificate uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  r text; cid uuid; course_id uuid; cert public.certificates%rowtype; rows jsonb;
  pending timestamp with time zone; claimed timestamp with time zone;
begin
  select sc.role, sc.company_id into r, cid from public.session_contexts sc
    where sc.user_id = p_user and sc.session_id = p_session and (
      (sc.role = 'gestor' and exists(select 1 from public.platform_gestors g where g.user_id = p_user)) or
      (sc.role in ('empresa','funcionario') and exists(select 1 from public.company_memberships m
        join public.companies c on c.id = m.company_id and c.active
        where m.user_id = p_user and m.company_id = sc.company_id and m.role = sc.role)));
  if r is null then raise exception 'Forbidden'; end if;
  if p_event = 'certificate_issued' then
    if p_certificate is null or p_course is not null or p_company is not null or r <> 'funcionario' then raise exception 'Forbidden'; end if;
    select * into cert from public.certificates where id = p_certificate and user_id = p_user and company_id = cid for update;
    if not found then raise exception 'Forbidden'; end if;
    if cert.push_claimed_at is not null or cert.issued_at < now() - interval '10 minutes' then
      return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb);
    end if;
    update public.certificates set push_claimed_at = now() where id = cert.id;
    course_id := cert.course_id;
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into rows from (
      select f.user_id, f.token, f.updated_at from public.fcm_tokens f
      left join public.notification_preferences np on np.user_id = f.user_id
      where f.user_id = p_user and coalesce(np.push_enabled, true)
      order by f.updated_at desc, f.token limit 101) t;
  elsif p_event = 'course_available' then
    if p_course is null or p_certificate is not null or (r <> 'gestor' and (r <> 'empresa' or p_company is distinct from cid)) then raise exception 'Forbidden'; end if;
    perform 1 from public.courses where id = p_course and status = 'released' for update;
    if not found then return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb); end if;
    if p_company is null then
      if r <> 'gestor' then raise exception 'Forbidden'; end if;
      select push_pending_at, push_claimed_at into pending, claimed from public.courses where id = p_course;
      if pending is null or pending < now() - interval '10 minutes' or (claimed is not null and claimed >= pending) then
        return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb);
      end if;
      update public.courses set push_pending_at = null, push_claimed_at = now() where id = p_course;
    else
      if not exists(select 1 from public.companies c where c.id = p_company and c.active)
        or not public.course_company_allowed(p_course, p_company)
        or not coalesce((select company_enabled from public.assignments where course_id = p_course and company_id = p_company), true) then
        return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb);
      end if;
      select push_pending_at, push_claimed_at into pending, claimed from public.assignments where course_id = p_course and company_id = p_company for update;
      if pending is null or pending < now() - interval '10 minutes' or (claimed is not null and claimed >= pending) then
        return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb);
      end if;
      update public.assignments set push_pending_at = null, push_claimed_at = now() where course_id = p_course and company_id = p_company;
    end if;
    course_id := p_course;
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) into rows from (
      select distinct f.user_id, f.token, f.updated_at from public.fcm_tokens f
      join public.company_memberships m on m.user_id = f.user_id and m.role = 'funcionario'
      join public.companies c on c.id = m.company_id and c.active
      left join public.notification_preferences np on np.user_id = f.user_id
      left join public.assignments a on a.course_id = p_course and a.company_id = c.id
      join public.courses course on course.id = p_course
      where (p_company is null or c.id = p_company) and coalesce(np.push_enabled, true)
        and course.status = 'released' and (course.all_companies or coalesce(a.released, false))
        and coalesce(a.company_enabled, true)
      order by f.updated_at desc, f.token, f.user_id limit 101) t;
  else raise exception 'Forbidden'; end if;
  return jsonb_build_object('suppressed', false, 'tokens', rows, 'course_id', course_id);
end $function$;

REVOKE ALL ON FUNCTION "public"."claim_push_recipients"(uuid, uuid, text, uuid, uuid, uuid) FROM PUBLIC, "anon", "authenticated";

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
declare was_all boolean;
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
  select all_companies into was_all from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  update public.courses set all_companies = p_all_companies,
    push_pending_at = case when status = 'released' and p_all_companies and not all_companies
      then now() else push_pending_at end where id = p_course;
  if not p_all_companies then
    insert into public.assignments(course_id, company_id, released, push_pending_at)
      select p_course, id, true, case when c.status = 'released' and not was_all then now() end
      from (select distinct unnest(p_company_ids) as id) ids
      cross join public.courses c where c.id = p_course
      on conflict (course_id, company_id) do update set released = true,
        push_pending_at = case when not public.assignments.released and not was_all and
          (select status = 'released' from public.courses where id = p_course)
          then now() else public.assignments.push_pending_at end;
    update public.assignments set released = false, push_pending_at = null
      where course_id = p_course and not (company_id = any(p_company_ids));
  end if;
end $function$;

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
    on conflict (course_id, company_id) do update set company_enabled = excluded.company_enabled,
      push_pending_at = case when excluded.company_enabled and not public.assignments.company_enabled
        and (select status = 'released' from public.courses where id = p_course)
        then now() when not excluded.company_enabled then null else public.assignments.push_pending_at end;
end $function$;

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
  update public.courses set status = case when p_enabled then 'released' else 'paused' end,
    push_pending_at = case when p_enabled and status <> 'released' then now()
      when not p_enabled then null else push_pending_at end
    where id = p_course;
  if not found then raise exception 'Course unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."claim_push_recipients"(uuid, uuid, text, uuid, uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."claim_push_recipients"(uuid, uuid, text, uuid, uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."claim_push_recipients"(uuid, uuid, text, uuid, uuid, uuid) TO "service_role";

REVOKE ALL ON TABLE "public"."assignments" FROM "authenticated";

REVOKE ALL ("company_enabled") ON TABLE "public"."assignments" FROM "authenticated";

GRANT INSERT ("company_enabled"), UPDATE ("company_enabled") ON TABLE "public"."assignments" TO "authenticated";

REVOKE ALL ("company_id") ON TABLE "public"."assignments" FROM "authenticated";

GRANT INSERT ("company_id"), UPDATE ("company_id") ON TABLE "public"."assignments" TO "authenticated";

REVOKE ALL ("course_id") ON TABLE "public"."assignments" FROM "authenticated";

GRANT INSERT ("course_id"), UPDATE ("course_id") ON TABLE "public"."assignments" TO "authenticated";

REVOKE ALL ("released") ON TABLE "public"."assignments" FROM "authenticated";

GRANT INSERT ("released"), UPDATE ("released") ON TABLE "public"."assignments" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."assignments" TO "authenticated";

REVOKE ALL ON TABLE "public"."courses" FROM "authenticated";

REVOKE ALL ("all_companies") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("all_companies"), UPDATE ("all_companies") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("cover_key") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("cover_key"), UPDATE ("cover_key") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("created_at") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("created_at"), UPDATE ("created_at") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("created_by") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("created_by"), UPDATE ("created_by") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("description") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("description"), UPDATE ("description") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("id"), UPDATE ("id") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("kind") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("kind"), UPDATE ("kind") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("responsible_id") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("responsible_id"), UPDATE ("responsible_id") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("status") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("status"), UPDATE ("status") ON TABLE "public"."courses" TO "authenticated";

REVOKE ALL ("title") ON TABLE "public"."courses" FROM "authenticated";

GRANT INSERT ("title"), UPDATE ("title") ON TABLE "public"."courses" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."courses" TO "authenticated";
