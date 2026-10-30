CREATE OR REPLACE FUNCTION public.update_course_lesson (
  p_lesson       uuid,
  p_module_title text,
  p_title        text,
  p_video_id     text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare existing public.lessons;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.lessons where id = p_lesson for update;
  if not found then raise exception 'Lesson unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    p_module_title is null or length(trim(p_module_title)) not between 1 and 200 or
    (existing.kind = 'video' and (p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$')) or
    (existing.kind <> 'video' and p_video_id is not null) then
    raise exception 'Invalid lesson';
  end if;
  update public.modules set title = trim(p_module_title) where id = existing.module_id;
  update public.lessons set title = trim(p_title),
    video_id = case when kind = 'video' then p_video_id else video_id end
    where id = p_lesson;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."update_course_lesson"(uuid, text, text, text) FROM PUBLIC, "anon", "service_role";
