-- The session-ID argument is required: an Edge Function authenticated with the
-- service role must prove that the accepting caller still has a live Auth session.
-- Keep the previous three-argument form as a thin secure wrapper so a deploy of
-- this migration before the invite handler cannot grant access without a session.
CREATE OR REPLACE FUNCTION public.accept_membership_invite (
  p_token_hash text,
  p_user       uuid,
  p_session    uuid,
  p_email      text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare invite public.membership_invites;
begin
  -- Revocation must be visible before any membership/gestor grant in this txn.
  perform public.require_live_session_id(p_user, p_session);
  lock table public.platform_gestors in share row exclusive mode;
  lock table public.company_memberships in share row exclusive mode;
  select * into invite from public.membership_invites
    where token_hash = p_token_hash and lower(email) = lower(p_email)
      and expires_at > now() for update;
  if not found or not exists (select 1 from public.profiles
    where id = p_user and lower(email) = lower(p_email)) then
    raise exception 'Invitation unavailable';
  end if;
  if invite.company_id is not null and not exists (
    select 1 from public.companies where id = invite.company_id and active) then
    raise exception 'Company unavailable';
  end if;
  if invite.role = 'gestor' then
    insert into public.platform_gestors(user_id) values (p_user) on conflict do nothing;
  else
    insert into public.company_memberships(user_id, company_id, role, dept, job_title)
      values (p_user, invite.company_id, invite.role, invite.dept, invite.job_title)
      on conflict (user_id, company_id, role) do update
        set dept = excluded.dept, job_title = excluded.job_title;
  end if;
  delete from public.membership_invites where id = invite.id;
end $function$;

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, uuid, text) TO "service_role", "postgres";

-- Legacy signature: the token is burned, but no access is granted without a
-- verifiable live session. Fails closed rather than silently keeping old access.
CREATE OR REPLACE FUNCTION public.accept_membership_invite (
  p_token_hash text,
  p_user       uuid,
  p_email      text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  raise exception 'Authentication required' using errcode = '42501';
end $function$;

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) FROM PUBLIC, "anon", "authenticated";
GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) TO "service_role", "postgres";
