CREATE OR REPLACE FUNCTION public.validate_lesson_content(p_kind text, p_data jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $function$
declare keys text[]; k text; q jsonb; frame int;
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text)>500000 or
    length(coalesce(p_data->>'body',''))>100000 then raise exception 'Invalid lesson'; end if;
  if p_data ? 'image_keys' and jsonb_typeof(p_data->'image_keys') <> 'array' then raise exception 'Invalid frames'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(p_data->'image_keys','[]')) v where jsonb_typeof(v) <> 'string') then raise exception 'Invalid frames'; end if;
  keys := array(select jsonb_array_elements_text(coalesce(p_data->'image_keys','[]')));
  k := nullif(p_data->>'file_key','');
  frame := coalesce((p_data->>'frame_ms')::int,1000);
  if frame not between 100 and 10000 or cardinality(keys)>100 or
    cardinality(keys) + (case when k is null then 0 else 1 end) > 100 then raise exception 'Invalid animation'; end if;
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
end $function$;
REVOKE ALL ON FUNCTION public.validate_lesson_content(text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_lesson_content(text, jsonb) TO postgres;
