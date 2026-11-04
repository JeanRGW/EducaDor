CREATE OR REPLACE FUNCTION public.complete_password_setup ()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.require_mfa_if_enrolled();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  -- Match Auth's HasPassword semantics; this is onboarding state, not reauthentication.
  perform 1 from auth.users where id = auth.uid()
    and coalesce(encrypted_password, '') <> '' for share;
  if not found then raise exception 'Password unavailable'; end if;
  update public.profiles set needs_password = false where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION public.complete_password_setup() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.complete_password_setup() TO authenticated, postgres;
