CREATE OR REPLACE FUNCTION public.update_course_metadata (
  p_course         uuid,
  p_title          text,
  p_description    text,
  p_cover_key      text,
  p_responsible_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare existing public.courses;
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  select * into existing from public.courses where id = p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or
    length(coalesce(p_description, '')) > 10000 then raise exception 'Invalid course'; end if;
  if p_cover_key is distinct from existing.cover_key and p_cover_key is not null and
    (length(p_cover_key) > 200 or p_cover_key !~ '^covers/[A-Za-z0-9_-]{1,120}\.webp$') then
    raise exception 'Invalid cover';
  end if;
  if p_responsible_id is distinct from existing.responsible_id and
    p_responsible_id is not null and not exists (
      select 1 from public.platform_gestors where user_id = p_responsible_id) then
    raise exception 'Invalid responsible';
  end if;
  update public.courses set title = trim(p_title), description = coalesce(p_description, ''),
    cover_key = p_cover_key, responsible_id = p_responsible_id where id = p_course;
  -- Never replace rows or alter status, audience, company preferences or points.
end $function$;

GRANT EXECUTE ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."update_course_metadata"(uuid, text, text, text, uuid) FROM PUBLIC, "anon", "service_role";
