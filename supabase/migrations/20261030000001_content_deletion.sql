-- Preserve the applied content migration. All hard deletes require an active gestor.
-- Existing foreign keys cascade children, assignments, progress and course certificates.
create function public.delete_content(p_kind text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
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
end $$;
revoke all on function public.delete_content(text,uuid) from public,anon;
grant execute on function public.delete_content(text,uuid) to authenticated;
