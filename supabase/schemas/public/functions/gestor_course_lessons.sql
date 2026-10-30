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

GRANT EXECUTE ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."gestor_course_lessons"(uuid, integer) FROM PUBLIC, "anon", "service_role";
