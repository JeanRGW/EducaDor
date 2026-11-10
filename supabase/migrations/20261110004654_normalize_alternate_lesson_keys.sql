SET local check_function_bodies = off;

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
declare result uuid; keys text[]; k text; frame int; gender text; alternate jsonb;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 or p_kind is null or
    p_kind not in ('video','audio','pdf','reading','quiz','animation') or p_data is null or
    jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text)>500000 or
    length(coalesce(p_data->>'body',''))>100000 then raise exception 'Invalid lesson'; end if;
  perform 1 from public.modules where id=p_module for update;
  if not found then raise exception 'Module unavailable'; end if;
  if p_lesson is not null then
    select content_gender, alternate_content into gender, alternate from public.lessons
      where id=p_lesson and module_id=p_module and kind=p_kind for update;
    if not found then raise exception 'Lesson unavailable or type changed'; end if;
  end if;
  if p_data ? 'content_gender' then gender := p_data->>'content_gender'; end if;
  if p_data ? 'alternate_content' then alternate := nullif(p_data->'alternate_content','null'::jsonb); end if;
  if gender is not null and gender not in ('male','female') then raise exception 'Invalid gender'; end if;
  perform public.validate_lesson_content(p_kind, p_data);
  if alternate is not null then
    if gender is null or jsonb_typeof(alternate)<>'object' then raise exception 'Invalid alternate'; end if;
    if exists(select 1 from jsonb_object_keys(alternate) key where key not in
      ('video_id','file_key','image_keys','frame_ms','body','questions')) then raise exception 'Invalid alternate field'; end if;
    perform public.validate_lesson_content(p_kind, alternate);
    if alternate ? 'file_key' then
      alternate := jsonb_set(alternate, '{file_key}', coalesce(to_jsonb(nullif(alternate->>'file_key','')), 'null'::jsonb));
    end if;
  end if;
  keys := array(select jsonb_array_elements_text(coalesce(p_data->'image_keys','[]')));
  k := nullif(p_data->>'file_key','');
  frame := coalesce((p_data->>'frame_ms')::int,1000);
  if p_lesson is null then
    insert into public.lessons(module_id,title,kind,position) select p_module,trim(p_title),p_kind,coalesce(max(position),0)+1
      from public.lessons where module_id=p_module returning id into result;
  else result := p_lesson; end if;
  update public.lessons set title=trim(p_title),
    content_gender=gender, alternate_content=alternate,
    points=case when p_data ? 'points' then (p_data->>'points')::int else points end,
    video_id=case when p_kind='video' then p_data->>'video_id' end,
    file_key=case when p_kind in ('audio','pdf','animation') then k end,
    body=coalesce(p_data->>'body',''),
    quiz_json=case when p_kind='quiz' then p_data->'questions' end,
    image_keys=case when p_kind='animation' then keys else '{}' end, frame_ms=frame where id=result;
  return result;
end $function$;
