CREATE OR REPLACE FUNCTION public.register_fcm_token(p_token text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_token is null or length(p_token) not between 1 and 4096 or
    p_token <> trim(p_token) or p_platform not in ('android', 'ios', 'web') or p_platform is null then
    raise exception 'Invalid token';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_token, 0));
  delete from public.fcm_tokens where token = p_token and user_id <> auth.uid();
  insert into public.fcm_tokens(user_id, token, platform, updated_at)
    values (auth.uid(), p_token, p_platform, now())
    on conflict (user_id, token) do update set platform = excluded.platform, updated_at = excluded.updated_at;
end $function$;

REVOKE ALL ON FUNCTION public.register_fcm_token(text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_fcm_token(text, text) TO authenticated;
