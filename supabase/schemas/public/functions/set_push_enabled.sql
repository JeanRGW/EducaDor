CREATE OR REPLACE FUNCTION public.set_push_enabled(p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_enabled is null then raise exception 'Invalid preference'; end if;
  insert into public.notification_preferences(user_id, push_enabled)
    values (auth.uid(), p_enabled)
    on conflict (user_id) do update set push_enabled = excluded.push_enabled;
end $function$;

REVOKE ALL ON FUNCTION public.set_push_enabled(boolean) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.set_push_enabled(boolean) TO authenticated;
