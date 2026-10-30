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

GRANT EXECUTE ON FUNCTION "public"."gestor_course_audience"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_course_audience"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_audience"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_course_audience"(uuid) FROM PUBLIC, "anon", "service_role";
