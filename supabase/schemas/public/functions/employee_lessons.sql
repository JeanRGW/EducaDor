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

GRANT EXECUTE ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_lessons"(uuid, uuid, integer) FROM PUBLIC, "anon", "service_role";
