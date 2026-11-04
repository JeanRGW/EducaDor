CREATE OR REPLACE FUNCTION public.publish_video_trail (
  p_title          text,
  p_description    text,
  p_module_title   text,
  p_video_id       text,
  p_all_companies  boolean DEFAULT true,
  p_company_ids    uuid[]  DEFAULT '{}'::uuid[],
  p_cover_key      text    DEFAULT NULL::text,
  p_responsible_id uuid    DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare course_id uuid; module_id uuid;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 or p_module_title is null or
    length(trim(p_module_title)) not between 1 and 200 or
    p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$' then
    raise exception 'Invalid trail';
  end if;
  if p_cover_key is not null and (length(p_cover_key) > 200 or
    p_cover_key !~ '^covers/[A-Za-z0-9_-]{1,120}\.webp$') then
    raise exception 'Invalid cover';
  end if;
  if p_responsible_id is not null and not exists (
    select 1 from public.platform_gestors g where g.user_id = p_responsible_id) then
    raise exception 'Invalid responsible';
  end if;
  insert into public.courses(title, kind, description, status, created_by,
    all_companies, cover_key, responsible_id)
    values (trim(p_title), 'course', coalesce(p_description, ''), 'paused',
      auth.uid(), true, p_cover_key, p_responsible_id)
    returning id into course_id;
  perform public.set_course_audience(course_id, p_all_companies, p_company_ids);
  insert into public.modules(course_id, title, position)
    values (course_id, trim(p_module_title), 1) returning id into module_id;
  insert into public.lessons(module_id, title, kind, video_provider, video_id, position)
    values (module_id, trim(p_title), 'video', 'youtube', p_video_id, 1);
  perform public.set_course_platform_enabled(course_id, true);
  return course_id;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."publish_video_trail"(text, text, text, text, boolean, uuid[], text, uuid) FROM PUBLIC, "anon", "service_role";
