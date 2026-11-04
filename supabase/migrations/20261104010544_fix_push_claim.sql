SET local check_function_bodies = off;

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
