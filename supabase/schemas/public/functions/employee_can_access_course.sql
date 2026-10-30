CREATE OR REPLACE FUNCTION public.employee_can_access_course (
  p_course uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(public.context_role() = 'funcionario', false)
    and exists (
      select 1 from public.courses c
      where c.id = p_course and c.status = 'released'
        and public.course_company_allowed(c.id, public.own_company_id())
        and coalesce((select a.company_enabled from public.assignments a
          where a.course_id = c.id and a.company_id = public.own_company_id()), true))
$function$;

GRANT EXECUTE ON FUNCTION "public"."employee_can_access_course"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_can_access_course"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_can_access_course"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_can_access_course"(uuid) FROM PUBLIC, "anon", "service_role";
