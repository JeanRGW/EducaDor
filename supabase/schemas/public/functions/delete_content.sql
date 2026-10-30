CREATE OR REPLACE FUNCTION public.delete_content (
  p_kind text,
  p_id   uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare parent uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_kind='course' then
    delete from public.courses where id=p_id;
  elsif p_kind='module' then
    select course_id into parent from public.modules where id=p_id;
    if not found then raise exception 'Content unavailable'; end if;
    perform 1 from public.courses where id=parent for update;
    delete from public.modules where id=p_id;
  elsif p_kind='lesson' then
    select module_id into parent from public.lessons where id=p_id;
    if not found then raise exception 'Content unavailable'; end if;
    perform 1 from public.modules where id=parent for update;
    delete from public.lessons where id=p_id;
  else raise exception 'Invalid content type';
  end if;
  if not found then raise exception 'Content unavailable'; end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."delete_content"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."delete_content"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."delete_content"(text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."delete_content"(text, uuid) FROM PUBLIC, "anon", "service_role";
