CREATE OR REPLACE FUNCTION public.require_mfa_if_enrolled()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- One shared gate for every authenticated request: a revoked session is denied
  -- even when its JWT is still unexpired, and enrolled accounts need aal2.
  perform public.require_live_session();
  if coalesce(auth.jwt()->>'aal', '') <> 'aal2' and exists (
    select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'
  ) then
    raise exception 'MFA verification required' using errcode = '42501';
  end if;
end
$function$;
REVOKE ALL ON FUNCTION public.require_mfa_if_enrolled() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.require_mfa_if_enrolled() TO authenticated, postgres;
