CREATE OR REPLACE FUNCTION public.employee_lesson_content(p_lesson uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario', false) then raise exception 'Forbidden'; end if;
  select public.resolved_lesson_content(l, p.gender) into result
    from public.lessons l join public.modules m on m.id = l.module_id
    join public.profiles p on p.id = auth.uid()
    where l.id = p_lesson and public.employee_can_access_course(m.course_id);
  if result is null then raise exception 'Lesson unavailable'; end if;
  return result;
end $function$;
REVOKE ALL ON FUNCTION public.employee_lesson_content(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.employee_lesson_content(uuid) TO authenticated, postgres;
