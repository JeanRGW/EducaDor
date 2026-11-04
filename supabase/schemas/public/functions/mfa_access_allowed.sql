CREATE OR REPLACE FUNCTION public.mfa_access_allowed()
  RETURNS boolean
  LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  return true;
end
$function$;
REVOKE ALL ON FUNCTION public.mfa_access_allowed() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.mfa_access_allowed() TO authenticated, postgres;
