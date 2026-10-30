-- Content is always a course containing modules containing typed lessons.
-- Consolidated, unapplied content migration: formats, mixed text/media, counts and ordering.
-- Preserve IDs, assignments, preferences and progress for legacy catalog items.
update public.courses set kind='course' where kind<>'course';
alter table public.lessons drop constraint lessons_kind_check;
alter table public.lessons add constraint lessons_kind_check check
  (kind in ('video','audio','pdf','quiz','reading','animation'));
alter table public.lessons add column body text not null default '';
alter table public.lessons add column image_keys text[] not null default '{}';
alter table public.lessons add column frame_ms int not null default 1000 check (frame_ms between 100 and 10000);

create or replace function public.employee_catalog(p_company uuid, p_search text default '', p_kind text default null,
  p_state text default null, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset<0 or p_offset is null or (p_kind is not null and p_kind not in ('video','audio','pdf','quiz','reading','animation'))
    or (p_state is not null and p_state not in ('not_started','in_progress','completed')) then raise exception 'Invalid query'; end if;
  with catalog as (
    select c.id,c.title,c.description,c.cover_key,count(l.id)::int as lesson_count,
      count(l.id) filter(where lp.status='completed')::int as completed_count,max(lp.updated_at) as last_activity_at,
      case when count(l.id)>0 and count(l.id)=count(l.id) filter(where lp.status='completed') then 'completed'
        when count(lp.lesson_id)>0 then 'in_progress' else 'not_started' end as state
    from public.courses c left join public.modules m on m.course_id=c.id left join public.lessons l on l.module_id=m.id
    left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=auth.uid() and lp.company_id=p_company
    where public.employee_can_access_course(c.id) and strpos(lower(c.title),lower(trim(coalesce(p_search,''))))>0
      and (p_kind is null or exists(select 1 from public.modules fm join public.lessons fl on fl.module_id=fm.id where fm.course_id=c.id and fl.kind=p_kind))
    group by c.id
  ), matching as (select * from catalog where p_state is null or state=p_state), page as (
    select * from matching order by last_activity_at desc nulls last,lower(title),id limit 50 offset p_offset
  ) select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(p) order by last_activity_at desc nulls last,lower(title),id) from page p),'[]'::jsonb)) into result;
  return result;
end $$;
update storage.buckets set allowed_mime_types = array['application/pdf','audio/mpeg','image/gif','image/png','image/jpeg','image/webp']
where id = 'educador-private';

create function public.create_content_course(p_title text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then raise exception 'Invalid title'; end if;
  insert into public.courses(title,kind,status,created_by,all_companies)
    values(trim(p_title),'course','paused',auth.uid(),true) returning id into result;
  return result;
end $$;

-- The additional return column requires recreating the function and its grants.
drop function public.content_catalog(text,text,int,int);
create function public.content_catalog(p_search text default '', p_kind text default null,
  p_offset int default 0, p_limit int default 50)
returns table(id uuid, title text, kind text, description text, cover_key text,
  platform_enabled boolean, all_companies boolean, company_enabled boolean,
  company_ids uuid[], company_count bigint, lesson_count bigint, completion_pct numeric, module_count bigint)
language plpgsql stable security definer set search_path = '' as $$
declare cid uuid := public.own_company_id(); platform boolean := coalesce(public.is_gestor(), false);
begin
  if not platform and (public.context_role() is distinct from 'empresa' or cid is null) then raise exception 'Forbidden'; end if;
  return query with page as (
    select c.* from public.courses c where (platform or public.course_company_allowed(c.id,cid))
      and (p_kind is null or p_kind='course' or exists(select 1 from public.modules m join public.lessons l on l.module_id=m.id where m.course_id=c.id and l.kind=p_kind))
      and (coalesce(p_search,'')='' or strpos(lower(c.title),lower(p_search))>0)
    order by c.created_at desc,c.id limit least(greatest(coalesce(p_limit,50),1),50) offset greatest(coalesce(p_offset,0),0)
  ) select c.id,c.title,c.kind,c.description,c.cover_key,c.status='released',c.all_companies,
    case when platform then true else coalesce((select a.company_enabled from public.assignments a where a.course_id=c.id and a.company_id=cid),true) end,
    case when platform then array(select a.company_id from public.assignments a where a.course_id=c.id and a.released order by a.company_id) else null::uuid[] end,
    case when platform then (select count(*) from public.companies co where co.active and public.course_company_allowed(c.id,co.id)) else 1::bigint end,
    (select count(*) from public.lessons l join public.modules m on m.id=l.module_id where m.course_id=c.id),
    (select round(100.0*count(*) filter(where lp.status='completed')/nullif(count(*),0),1)
      from public.modules m join public.lessons l on l.module_id=m.id
      join public.company_memberships cm on cm.role='funcionario' join public.companies co on co.id=cm.company_id and co.active
      left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=cm.user_id and lp.company_id=cm.company_id
      where m.course_id=c.id and public.course_company_allowed(c.id,cm.company_id) and (platform or cm.company_id=cid)),
    (select count(*) from public.modules m where m.course_id=c.id)
  from page c order by c.created_at desc,c.id;
end $$;

revoke all on function public.content_catalog(text,text,int,int) from public,anon;
grant execute on function public.content_catalog(text,text,int,int) to authenticated;

create function public.save_content_module(p_course uuid,p_title text,p_module uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result uuid;
begin
  if not coalesce(public.is_gestor(),false) then raise exception 'Forbidden'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200 then raise exception 'Invalid title'; end if;
  perform 1 from public.courses where id=p_course for update;
  if not found then raise exception 'Course unavailable'; end if;
  if p_module is null then
    insert into public.modules(course_id,title,position) select p_course,trim(p_title),coalesce(max(position),0)+1
      from public.modules where course_id=p_course returning id into result;
  else
    update public.modules set title=trim(p_title) where id=p_module and course_id=p_course returning id into result;
    if not found then raise exception 'Module unavailable'; end if;
  end if;
  return result;
end $$;

create function public.save_content_lesson(p_module uuid,p_title text,p_kind text,p_data jsonb,p_lesson uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
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
end $$;

revoke all on function public.create_content_course(text),public.save_content_module(uuid,text,uuid),public.save_content_lesson(uuid,text,text,jsonb,uuid) from public,anon;
grant execute on function public.create_content_course(text),public.save_content_module(uuid,text,uuid),public.save_content_lesson(uuid,text,text,jsonb,uuid) to authenticated;

create or replace function public.save_employee_progress(p_company uuid, p_lesson uuid, p_position int, p_completed boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
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
      else false end for share of c;
  if not found then raise exception 'Lesson unavailable'; end if;
  -- All formats use the same company-scoped progress; completion is client-reported MVP.
  insert into public.lesson_progress(user_id,company_id,lesson_id,status,position_sec)
    values(auth.uid(),p_company,p_lesson,case when p_completed then 'completed' else 'in_progress' end,p_position)
    on conflict(user_id,company_id,lesson_id) do update set
      status=case when lesson_progress.status='completed' or p_completed then 'completed' else 'in_progress' end,
      position_sec=excluded.position_sec,updated_at=now();
end $$;

-- Serialize sibling edits on the same parent, including creates from the editor.
-- Renumbering also handles legacy duplicate positions. IDs and progress never change.
create function public.move_content_item(p_kind text,p_id uuid,p_direction int)
returns void language plpgsql security definer set search_path='' as $$
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
end $$;
revoke all on function public.move_content_item(text,uuid,int) from public,anon;
grant execute on function public.move_content_item(text,uuid,int) to authenticated;
