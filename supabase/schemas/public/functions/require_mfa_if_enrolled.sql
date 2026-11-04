CREATE OR REPLACE FUNCTION public.require_mfa_if_enrolled()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if coalesce(auth.jwt()->>'aal', '') <> 'aal2' and exists (
    select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified'
  ) then
    raise exception 'MFA verification required' using errcode = '42501';
  end if;
end
$function$;
REVOKE ALL ON FUNCTION public.require_mfa_if_enrolled() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.require_mfa_if_enrolled() TO authenticated, postgres;
