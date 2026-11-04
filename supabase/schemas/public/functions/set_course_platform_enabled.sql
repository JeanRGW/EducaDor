CREATE OR REPLACE FUNCTION public.set_course_platform_enabled (
  p_course  uuid,
  p_enabled boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_enabled is null then raise exception 'Invalid state'; end if;
  update public.courses set status = case when p_enabled then 'released' else 'paused' end,
    push_pending_at = case when p_enabled and status <> 'released' then now()
      when not p_enabled then null else push_pending_at end
    where id = p_course;
  if not found then raise exception 'Course unavailable'; end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) TO "postgres";

REVOKE ALL ON FUNCTION "public"."set_course_platform_enabled"(uuid, boolean) FROM PUBLIC, "anon", "service_role";
