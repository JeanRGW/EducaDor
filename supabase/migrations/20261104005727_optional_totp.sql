SET local check_function_bodies = off;

DROP POLICY "certificates_select" ON "public"."certificates";

DROP POLICY "company_memberships_select" ON "public"."company_memberships";

DROP POLICY "progress_insert" ON "public"."lesson_progress";

DROP POLICY "progress_select" ON "public"."lesson_progress";

DROP POLICY "progress_update" ON "public"."lesson_progress";

DROP POLICY "profiles_select" ON "public"."profiles";

DROP POLICY "redemptions_select" ON "public"."redemptions";

DROP POLICY "rewards_select" ON "public"."rewards";

DROP VIEW "public"."completion_by_company";

DROP VIEW "public"."completion_by_dept";

DROP VIEW "public"."engagement_monthly";

DROP VIEW "public"."popular_content";

DROP FUNCTION "public"."available_contexts"();

DROP FUNCTION "public"."context_role"();

CREATE OR REPLACE FUNCTION public.available_contexts()
  RETURNS TABLE (
    role         text,
    company_id   uuid,
    company_name text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return query select 'gestor'::text, null::uuid, 'Plataforma'::text
  from public.platform_gestors pg where pg.user_id = (select auth.uid())
  union all
  select cm.role, cm.company_id, c.name from public.company_memberships cm
    join public.companies c on c.id = cm.company_id and c.active
  where cm.user_id = (select auth.uid())
  order by 1, 3;
end
$function$;

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.complete_password_setup()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  -- Match Auth's HasPassword semantics; this is onboarding state, not reauthentication.
  perform 1 from auth.users where id = auth.uid()
    and coalesce(encrypted_password, '') <> '' for share;
  if not found then raise exception 'Password unavailable'; end if;
  update public.profiles set needs_password = false where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.context_role()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return (select sc.role from public.session_contexts sc
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
  limit 1);
end
$function$;

REVOKE ALL ON FUNCTION "public"."context_role"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.mfa_access_allowed()
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return true;
end
$function$;

REVOKE ALL ON FUNCTION "public"."mfa_access_allowed"() FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.require_mfa_if_enrolled()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if coalesce(auth.jwt()->>'aal', '') <> 'aal2' and exists (
    select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'
  ) then
    raise exception 'MFA verification required' using errcode = '42501';
  end if;
end
$function$;

REVOKE ALL ON FUNCTION "public"."require_mfa_if_enrolled"() FROM PUBLIC, "anon", "service_role";

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
  perform public.require_mfa_if_enrolled();
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
  perform public.require_mfa_if_enrolled();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 200 or
    length(coalesce(p_phone, '')) > 50 or length(coalesce(p_address, '')) > 500 or
    p_birth_date > current_date then raise exception 'Invalid profile'; end if;
  update public.profiles set full_name = trim(p_name),
    phone = nullif(trim(p_phone), ''), birth_date = p_birth_date,
    address = nullif(trim(p_address), '') where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

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

CREATE POLICY "certificates_select" ON "public"."certificates"
  FOR SELECT
  TO "authenticated"
  USING
    ((public.is_gestor() OR ((company_id = public.own_company_id()) AND ((public.context_role() = 'empresa'::text) OR ((public.context_role() = 'funcionario'::text) AND (user_id =
    auth.uid()))))));

CREATE POLICY "company_memberships_select" ON "public"."company_memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (company_id = public.own_company_id()))));

CREATE POLICY "mfa_memberships" ON "public"."company_memberships"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "mfa_fcm" ON "public"."fcm_tokens"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

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

CREATE POLICY "mfa_gestors" ON "public"."platform_gestors"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "mfa_profiles" ON "public"."profiles"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "profiles_select" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (((id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (EXISTS ( SELECT 1
   FROM public.company_memberships cm
  WHERE ((cm.user_id = profiles.id) AND (cm.company_id = public.own_company_id())))))));

CREATE POLICY "redemptions_select" ON "public"."redemptions"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR ((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()))));

CREATE POLICY "rewards_select" ON "public"."rewards"
  FOR SELECT
  TO "authenticated"
  USING ((active AND (public.is_gestor() OR (public.context_role() = 'funcionario'::text))));

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."available_contexts"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."available_contexts"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."context_role"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."context_role"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."mfa_access_allowed"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."mfa_access_allowed"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."mfa_access_allowed"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."require_mfa_if_enrolled"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."require_mfa_if_enrolled"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."require_mfa_if_enrolled"() TO "postgres";

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
