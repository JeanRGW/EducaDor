CREATE OR REPLACE FUNCTION public.create_content_course (
  p_title text
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
  insert into public.courses(title,kind,status,created_by,all_companies)
    values(trim(p_title),'course','paused',auth.uid(),true) returning id into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."create_content_course"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."create_content_course"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."create_content_course"(text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."create_content_course"(text) FROM PUBLIC, "anon", "service_role";
