CREATE OR REPLACE FUNCTION public.employee_progress_valid (
  p_lesson uuid,
  p_status text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(public.context_role() = 'funcionario', false)
    and p_status in ('in_progress', 'completed') and not exists (
      select 1 from public.lesson_progress lp where lp.user_id = auth.uid()
        and lp.company_id = public.own_company_id() and lp.lesson_id = p_lesson
        and lp.status = 'completed' and p_status <> 'completed')
$function$;

GRANT EXECUTE ON FUNCTION "public"."employee_progress_valid"(uuid, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_progress_valid"(uuid, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_progress_valid"(uuid, text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_progress_valid"(uuid, text) FROM PUBLIC, "anon", "service_role";
