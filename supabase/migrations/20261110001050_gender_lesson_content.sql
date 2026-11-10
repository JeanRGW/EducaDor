SET local check_function_bodies = off;

ALTER TABLE "public"."lesson_progress"
  ADD COLUMN "content_gender" text;

ALTER TABLE "public"."lessons"
  ADD COLUMN "content_gender" text;

ALTER TABLE "public"."lessons"
  ADD COLUMN "alternate_content" jsonb;

ALTER TABLE "public"."profiles"
  ADD COLUMN "gender" text;

CREATE OR REPLACE FUNCTION public.employee_lesson_content (
  p_lesson uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario', false) then raise exception 'Forbidden'; end if;
  select public.resolved_lesson_content(l, p.gender) into result
    from public.lessons l join public.modules m on m.id = l.module_id
    join public.profiles p on p.id = auth.uid()
    where l.id = p_lesson and public.employee_can_access_course(m.course_id);
  if result is null then raise exception 'Lesson unavailable'; end if;
  return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."employee_lesson_content"(uuid) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.employee_lessons (
  p_company uuid,
  p_course  uuid,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if not public.employee_can_access_course(p_course) then raise exception 'Course unavailable'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total', (select count(*) from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course),
    'items', coalesce((select jsonb_agg(to_jsonb(page) order by module_position, module_id, position, id) from (
       select l.id, l.title, l.kind, effective.content->>'video_id' as video_id,
         effective.content->>'content_gender' as content_gender, m.id as module_id, m.title as module_title,
        m.position as module_position, l.position, coalesce(lp.status,'not_started') as status,
         case when lp.content_gender is not distinct from (effective.content->>'content_gender')
           then greatest(coalesce(lp.position_sec,0),0) else 0 end as position_sec
       from public.modules m join public.lessons l on l.module_id = m.id
       join public.profiles p on p.id = auth.uid()
       cross join lateral (select public.resolved_lesson_content(l, p.gender) as content) effective
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = auth.uid() and lp.company_id = p_company
      where m.course_id = p_course order by m.position, m.id, l.position, l.id limit 50 offset p_offset
    ) page),'[]'::jsonb)) into result;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.resolved_lesson_content (
  p_lesson public.lessons,
  p_gender text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  SELECT CASE WHEN p_lesson.alternate_content IS NOT NULL
      AND p_gender IS NOT NULL AND p_gender <> p_lesson.content_gender
    THEN (to_jsonb(p_lesson) - 'alternate_content') || jsonb_build_object(
      'content_gender', p_gender,
      'video_id', p_lesson.alternate_content->'video_id',
      'file_key', p_lesson.alternate_content->'file_key',
      'image_keys', coalesce(p_lesson.alternate_content->'image_keys','[]'::jsonb),
      'frame_ms', coalesce(p_lesson.alternate_content->'frame_ms','1000'::jsonb),
      'body', coalesce(p_lesson.alternate_content->'body','""'::jsonb),
      'quiz_json', p_lesson.alternate_content->'questions')
    ELSE to_jsonb(p_lesson) - 'alternate_content' END;
$function$;

REVOKE ALL ON FUNCTION "public"."resolved_lesson_content"(public.lessons, text) FROM PUBLIC, "anon", "authenticated", "service_role";

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

CREATE OR REPLACE FUNCTION public.save_employee_progress (
  p_company   uuid,
  p_lesson    uuid,
  p_position  integer,
  p_completed boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.save_employee_progress(p_company, p_lesson, p_position, p_completed, null::text);
end $function$;

CREATE OR REPLACE FUNCTION public.save_employee_progress (
  p_company        uuid,
  p_lesson         uuid,
  p_position       integer,
  p_completed      boolean,
  p_content_gender text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  if p_position is null or p_position < 0 or p_completed is null then raise exception 'Invalid progress'; end if;
  perform 1 from public.lessons l join public.modules m on m.id=l.module_id join public.courses c on c.id=m.course_id
    where l.id=p_lesson and public.employee_can_access_course(m.course_id) and case l.kind
      when 'video' then l.video_id is not null
      when 'audio' then l.file_key is not null
      when 'pdf' then l.file_key is not null
      when 'reading' then length(trim(l.body))>0
      when 'animation' then l.file_key is not null or cardinality(l.image_keys)>=2
      when 'quiz' then case when jsonb_typeof(l.quiz_json)='array' then jsonb_array_length(l.quiz_json)>0 else false end
      else false end
    and (p_content_gender is null or (p_content_gender in ('male','female') and
      (l.content_gender=p_content_gender or (l.content_gender is not null and l.alternate_content is not null))))
    for share of c,l;
  if not found then raise exception 'Lesson unavailable'; end if;
  -- Version affects resume only; completion and rewards remain company/lesson scoped.
  insert into public.lesson_progress(user_id,company_id,lesson_id,status,position_sec,content_gender)
    values(auth.uid(),p_company,p_lesson,case when p_completed then 'completed' else 'in_progress' end,p_position,p_content_gender)
    on conflict(user_id,company_id,lesson_id) do update set
      status=case when lesson_progress.status='completed' or p_completed then 'completed' else 'in_progress' end,
      position_sec=excluded.position_sec,content_gender=excluded.content_gender,updated_at=now();
end $function$;

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean, text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.update_own_profile (
  p_name       text,
  p_phone      text,
  p_birth_date date,
  p_address    text,
  p_gender     text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if p_gender is not null and p_gender not in ('male','female') then raise exception 'Invalid gender'; end if;
  perform public.update_own_profile(p_name, p_phone, p_birth_date, p_address);
  update public.profiles set gender=p_gender where id=auth.uid();
end $function$;

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text, text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.validate_lesson_content (
  p_kind text,
  p_data jsonb
)
  RETURNS void
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
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

REVOKE ALL ON FUNCTION "public"."validate_lesson_content"(text, jsonb) FROM PUBLIC, "anon", "authenticated", "service_role";

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "lesson_progress_content_gender_check" CHECK ((content_gender = ANY (ARRAY['male'::text, 'female'::text])));

ALTER TABLE "public"."lessons"
  ADD CONSTRAINT "lessons_alternate_content_check" CHECK (((alternate_content IS NULL) OR ((content_gender IS
    NOT NULL) AND (jsonb_typeof(alternate_content) = 'object'::text) AND (octet_length((alternate_content)::text) <= 500000))));

ALTER TABLE "public"."lessons"
  ADD CONSTRAINT "lessons_content_gender_check" CHECK ((content_gender = ANY (ARRAY['male'::text, 'female'::text])));

ALTER TABLE "public"."profiles"
  ADD CONSTRAINT "profiles_gender_check" CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text])));

GRANT EXECUTE ON FUNCTION "public"."employee_lesson_content"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_lesson_content"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_lesson_content"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."resolved_lesson_content"(public.lessons, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."resolved_lesson_content"(public.lessons, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."save_employee_progress"(uuid, uuid, integer, boolean, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."update_own_profile"(text, text, date, text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."update_own_profile"(text, text, date, text, text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."validate_lesson_content"(text, jsonb) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."validate_lesson_content"(text, jsonb) TO "postgres";
