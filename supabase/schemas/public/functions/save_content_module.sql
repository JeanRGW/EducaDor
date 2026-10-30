CREATE OR REPLACE FUNCTION public.save_content_module (
  p_course uuid,
  p_title  text,
  p_module uuid DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then raise exception 'Invalid title'; end if;
  perform 1 from public.courses where id=p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_module is null then
    insert into public.modules(course_id,title,position) select p_course,trim(p_title),coalesce(max(position),0)+1
      from public.modules where course_id=p_course returning id into result;
  else
    update public.modules set title=trim(p_title) where id=p_module and course_id=p_course returning id into result;
    if not found then raise exception 'Module unavailable'; end if;
  end if;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."save_content_module"(uuid, text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_content_module"(uuid, text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_module"(uuid, text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."save_content_module"(uuid, text, uuid) FROM PUBLIC, "anon", "service_role";
