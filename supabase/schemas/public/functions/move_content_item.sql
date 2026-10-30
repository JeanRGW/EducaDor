CREATE OR REPLACE FUNCTION public.move_content_item (
  p_kind      text,
  p_id        uuid,
  p_direction integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare parent uuid; ids uuid[]; current_index int; target_index int; other uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_kind is null or p_kind not in ('module','lesson') or p_direction is null or p_direction not in (-1,1) then raise exception 'Invalid move'; end if;
  if p_kind='module' then
    select course_id into parent from public.modules where id=p_id;
    if not found then raise exception 'Module unavailable'; end if;
    perform 1 from public.courses where id=parent for update;
    select array_agg(id order by position,id) into ids from public.modules where course_id=parent;
  else
    select module_id into parent from public.lessons where id=p_id;
    if not found then raise exception 'Lesson unavailable'; end if;
    perform 1 from public.modules where id=parent for update;
    select array_agg(id order by position,id) into ids from public.lessons where module_id=parent;
  end if;
  current_index:=array_position(ids,p_id);
  if current_index is null then raise exception 'Content unavailable'; end if;
  target_index:=current_index+p_direction;
  if target_index<1 or target_index>cardinality(ids) then return; end if;
  other:=ids[target_index]; ids[target_index]:=p_id; ids[current_index]:=other;
  if p_kind='module' then
    update public.modules m set position=s.ordinality::int from unnest(ids) with ordinality s(id,ordinality) where m.id=s.id;
  else
    update public.lessons l set position=s.ordinality::int from unnest(ids) with ordinality s(id,ordinality) where l.id=s.id;
  end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."move_content_item"(text, uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."move_content_item"(text, uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."move_content_item"(text, uuid, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."move_content_item"(text, uuid, integer) FROM PUBLIC, "anon", "service_role";
