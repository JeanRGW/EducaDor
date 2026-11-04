CREATE OR REPLACE FUNCTION public.unregister_fcm_token(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_token is null or length(p_token) not between 1 and 4096 then raise exception 'Invalid token'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_token, 0));
  delete from public.fcm_tokens where user_id = auth.uid() and token = p_token;
end $function$;

REVOKE ALL ON FUNCTION public.unregister_fcm_token(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.unregister_fcm_token(text) TO authenticated;
