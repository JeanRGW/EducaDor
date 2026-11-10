CREATE OR REPLACE FUNCTION public.save_employee_progress (
  p_company uuid, p_lesson uuid, p_position integer, p_completed boolean, p_content_gender text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
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
REVOKE ALL ON FUNCTION public.save_employee_progress(uuid, uuid, integer, boolean, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_employee_progress(uuid, uuid, integer, boolean, text) TO authenticated, postgres;
