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

GRANT EXECUTE ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) TO "postgres";

REVOKE ALL ON FUNCTION "public"."set_course_audience"(uuid, boolean, uuid[]) FROM PUBLIC, "anon", "service_role";
