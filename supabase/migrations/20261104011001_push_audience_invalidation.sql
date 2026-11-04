SET local check_function_bodies = off;

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
  if not p_all_companies then
    update public.courses set push_pending_at = null where id = p_course and was_all;
  else
    update public.assignments set push_pending_at = null where course_id = p_course;
  end if;
  update public.courses set all_companies = p_all_companies,
    push_pending_at = case when status = 'released' and p_all_companies and not all_companies
      then now() else push_pending_at end where id = p_course;
  if not p_all_companies then
    insert into public.assignments(course_id, company_id, released, push_pending_at)
      select p_course, ids.id, true, case when c.status = 'released' and not was_all then now() end
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
