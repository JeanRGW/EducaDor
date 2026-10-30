CREATE OR REPLACE FUNCTION public.save_content_lesson (
  p_module uuid,
  p_title  text,
  p_kind   text,
  p_data   jsonb,
  p_lesson uuid  DEFAULT NULL::uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid; keys text[]; k text; q jsonb; frame int;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or p_kind is null or
    p_kind not in ('video','audio','pdf','reading','quiz','animation') or p_data is null or
    jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text)>500000 or
    length(coalesce(p_data->>'body',''))>100000 then raise exception 'Invalid lesson'; end if;
  perform 1 from public.modules where id=p_module for update;
  if not found then raise exception 'Module unavailable'; end if;
  if p_lesson is not null and not exists(select 1 from public.lessons where id=p_lesson and module_id=p_module and kind=p_kind) then
    raise exception 'Lesson unavailable or type changed'; end if;
  keys := array(select jsonb_array_elements_text(coalesce(p_data->'image_keys','[]')));
  k := nullif(p_data->>'file_key','');
  frame := coalesce((p_data->>'frame_ms')::int,1000);
  if frame not between 100 and 10000 or cardinality(keys)>100 then raise exception 'Invalid animation'; end if;
  if k is not null and k !~ '^lessons/[a-f0-9-]{36}\.(pdf|mp3|gif|png|jpg|webp)$' then raise exception 'Invalid file'; end if;
  if exists(select 1 from unnest(keys) key where key !~ '^lessons/[a-f0-9-]{36}\.(png|jpg|webp)$') then raise exception 'Invalid frame'; end if;
  if (p_kind='video' and coalesce(p_data->>'video_id','') !~ '^[A-Za-z0-9_-]{11}$') or
     (p_kind='audio' and coalesce(k,'') !~ '\.mp3$') or
     (p_kind='pdf' and coalesce(k,'') !~ '\.pdf$') or
     (p_kind='reading' and length(trim(coalesce(p_data->>'body',''))) not between 1 and 100000) or
     (p_kind='animation' and not ((coalesce(k,'') ~ '\.(gif|png|jpg|webp)$' and cardinality(keys)=0) or (k is null and cardinality(keys) between 2 and 100))) then
    raise exception 'Missing content'; end if;
  if p_kind='quiz' then
    if jsonb_typeof(p_data->'questions') is distinct from 'array' then raise exception 'Invalid quiz'; end if;
    if jsonb_array_length(p_data->'questions') not between 1 and 50 then raise exception 'Invalid quiz'; end if;
    for q in select jsonb_array_elements(p_data->'questions') loop
      if length(trim(coalesce(q->>'question',''))) not between 1 and 1000 or jsonb_typeof(q->'options') is distinct from 'array' then raise exception 'Invalid question'; end if;
      if jsonb_array_length(q->'options') not between 2 and 6 or (q->>'answer')::int not between 0 and jsonb_array_length(q->'options')-1 or q->>'answer' is null or
        exists(select 1 from jsonb_array_elements(q->'options') o where jsonb_typeof(o)<>'string' or length(trim(o #>> '{}')) not between 1 and 500) then raise exception 'Invalid answers'; end if;
    end loop;
  end if;
  if p_lesson is null then
    insert into public.lessons(module_id,title,kind,position) select p_module,trim(p_title),p_kind,coalesce(max(position),0)+1
      from public.lessons where module_id=p_module returning id into result;
  else result := p_lesson; end if;
  update public.lessons set title=trim(p_title), video_id=case when p_kind='video' then p_data->>'video_id' end,
    file_key=case when p_kind in ('audio','pdf','animation') then k end,
    body=coalesce(p_data->>'body',''),
    quiz_json=case when p_kind='quiz' then p_data->'questions' end,
    image_keys=case when p_kind='animation' then keys else '{}' end, frame_ms=frame where id=result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."save_content_lesson"(uuid, text, text, jsonb, uuid) FROM PUBLIC, "anon", "service_role";
