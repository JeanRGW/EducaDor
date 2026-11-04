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

GRANT EXECUTE ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) TO "postgres";

REVOKE ALL ON FUNCTION "public"."set_course_company_enabled"(uuid, boolean) FROM PUBLIC, "anon", "service_role";
