-- Fail-closed check binding the signed JWT to a live Auth session.
-- A password reset or factor removal deletes/changes auth.sessions rows while a
-- previously issued access token can remain unexpired; every authenticated entry
-- point therefore re-checks the current session row instead of trusting claims.
CREATE OR REPLACE FUNCTION public.require_live_session()
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  sid := nullif(auth.jwt()->>'session_id', '')::uuid;
  if sid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  -- "not_after" is Auth's session expiry; unexpired tokens keep working until then.
  if not exists (
    select 1 from auth.sessions s
    where s.id = sid and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
  ) then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
exception
  -- A malformed session_id claim is not a live session, never a 500.
  when invalid_text_representation then
    raise exception 'Authentication required' using errcode = '42501';
end
$function$;
REVOKE ALL ON FUNCTION public.require_live_session() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.require_live_session() TO authenticated, postgres;

-- Transactional variant for server-side functions that receive user/session IDs
-- from an Edge Function instead of a JWT. A matching row is locked for share so a
-- concurrent revocation either commits before this transaction reads it (denial)
-- or waits for this transaction to end. Callers must only honor the result inside
-- the same transaction as the mutation; a later revocation wins.
CREATE OR REPLACE FUNCTION public.require_live_session_id(p_user uuid, p_session uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if p_user is null or p_session is null then raise exception 'Forbidden'; end if;
  perform 1 from auth.sessions s
    where s.id = p_session and s.user_id = p_user
      and (s.not_after is null or s.not_after > now())
    for share;
  if not found then raise exception 'Forbidden'; end if;
end
$function$;
REVOKE ALL ON FUNCTION public.require_live_session_id(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_live_session_id(uuid, uuid) TO service_role, postgres;
