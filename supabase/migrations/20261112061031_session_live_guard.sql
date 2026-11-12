SET local check_function_bodies = off;

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
begin
  raise exception 'Authentication required' using errcode = '42501';
end $function$;

CREATE OR REPLACE FUNCTION public.accept_membership_invite (
  p_token_hash text,
  p_user       uuid,
  p_session    uuid,
  p_email      text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare invite public.membership_invites;
begin
  -- Revocation must be visible before any membership/gestor grant in this txn.
  perform public.require_live_session_id(p_user, p_session);
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

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) FROM PUBLIC, "anon", "authenticated";

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
  r text; cid uuid; result_course uuid; cert public.certificates%rowtype; rows jsonb;
  pending timestamp with time zone; claimed timestamp with time zone;
begin
  -- Service-role calls bypass RLS: revalidate the claimed session first.
  perform public.require_live_session_id(p_user, p_session);
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
    result_course := cert.course_id;
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
      if pending is null or pending < now() - interval '10 minutes' or (claimed is not null and (claimed >= pending or claimed > now() - interval '5 minutes')) then
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
      if pending is null or pending < now() - interval '10 minutes' or (claimed is not null and (claimed >= pending or claimed > now() - interval '5 minutes')) then
        return jsonb_build_object('suppressed', true, 'tokens', '[]'::jsonb);
      end if;
      update public.assignments set push_pending_at = null, push_claimed_at = now() where course_id = p_course and company_id = p_company;
    end if;
    result_course := p_course;
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
  return jsonb_build_object('suppressed', false, 'tokens', rows, 'course_id', result_course);
end $function$;

CREATE OR REPLACE FUNCTION public.issue_employee_certificate (
  p_user    uuid,
  p_session uuid,
  p_company uuid,
  p_course  uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid; prefix text; code_value text;
begin
  perform pg_advisory_xact_lock(hashtext(p_user::text || p_company::text || p_course::text));
  -- Serialize with revocation before trusting the session context.
  perform public.require_live_session_id(p_user, p_session);
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
  if found then return jsonb_build_object('id', result, 'created', false); end if;
  select co.code_prefix into prefix from public.companies co where co.id = p_company;
  for attempt in 1..10 loop
    code_value := prefix || '-';
    for digit in 1..6 loop code_value := code_value || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ',1+floor(random()*32)::int,1); end loop;
    begin
      insert into public.certificates(user_id,company_id,course_id,code) values(p_user,p_company,p_course,code_value) returning id into result;
      return jsonb_build_object('id', result, 'created', true);
    exception when unique_violation then null;
    end;
  end loop;
  raise exception 'Certificate code unavailable';
end $function$;

CREATE OR REPLACE FUNCTION public.require_live_session()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  sid := nullif(auth.jwt()->>'session_id', '')::uuid;
  if sid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  -- "not_after" is Auth's session expiry; unexpired tokens keep working until then.
  if not exists (
    select 1 from auth.sessions s
    where s.id = sid and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
  ) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
exception
  -- A malformed session_id claim is not a live session, never a 500.
  when invalid_text_representation then
    raise exception 'Authentication required' using errcode = '42501';
end
$function$;

REVOKE ALL ON FUNCTION "public"."require_live_session"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.require_live_session_id (
  p_user    uuid,
  p_session uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if p_user is null or p_session is null then raise exception 'Forbidden'; end if;
  perform 1 from auth.sessions s
    where s.id = p_session and s.user_id = p_user
      and (s.not_after is null or s.not_after > now())
    for share;
  if not found then raise exception 'Forbidden'; end if;
end
$function$;

REVOKE ALL ON FUNCTION "public"."require_live_session_id"(uuid, uuid) FROM PUBLIC, "anon", "authenticated";

CREATE OR REPLACE FUNCTION public.require_mfa_if_enrolled()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- One shared gate for every authenticated request: a revoked session is denied
  -- even when its JWT is still unexpired, and enrolled accounts need aal2.
  perform public.require_live_session();
  if coalesce(auth.jwt()->>'aal', '') <> 'aal2' and exists (
    select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'
  ) then
    raise exception 'MFA verification required' using errcode = '42501';
  end if;
end
$function$;

CREATE POLICY "session_live_assignments" ON "public"."assignments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_certificates" ON "public"."certificates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_companies" ON "public"."companies"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_courses" ON "public"."courses"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_lesson_progress" ON "public"."lesson_progress"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_lessons" ON "public"."lessons"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_modules" ON "public"."modules"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_redemptions" ON "public"."redemptions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "session_live_rewards" ON "public"."rewards"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "storage_public_session" ON "storage"."objects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."require_live_session"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."require_live_session"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."require_live_session"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."require_live_session_id"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."require_live_session_id"(uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."require_live_session_id"(uuid, uuid) TO "service_role";
