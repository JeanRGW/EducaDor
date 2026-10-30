CREATE OR REPLACE FUNCTION public.course_company_allowed (
  p_course  uuid,
  p_company uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from public.courses c where c.id = p_course and
      (c.all_companies or exists (
        select 1 from public.assignments a where a.course_id = c.id
          and a.company_id = p_company and a.released)))
$function$;

REVOKE ALL ON FUNCTION "public"."course_company_allowed"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."course_company_allowed"(uuid, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."course_company_allowed"(uuid, uuid) FROM PUBLIC, "anon", "authenticated", "service_role";
