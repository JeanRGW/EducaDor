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
declare invite public.membership_invites;
begin
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

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) TO "postgres";

REVOKE ALL ON FUNCTION "public"."accept_membership_invite"(text, uuid, text) FROM PUBLIC, "anon", "authenticated";
