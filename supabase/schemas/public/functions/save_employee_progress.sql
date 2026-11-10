CREATE OR REPLACE FUNCTION public.save_employee_progress (
  p_company   uuid,
  p_lesson    uuid,
  p_position  integer,
  p_completed boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.save_employee_progress(p_company, p_lesson, p_position, p_completed, null::text);
end $function$;

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) TO "postgres";

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean) FROM PUBLIC, "anon", "service_role";
