CREATE OR REPLACE FUNCTION public.revoke_gestor_access (
  p_user    uuid,
  p_company uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_company is null then
    -- Serialize removals and grant writes; two simultaneous removals cannot
    -- each observe the other gestor and leave the platform without one.
    lock table public.platform_gestors in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.platform_gestors where user_id = p_user) then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.platform_gestors) <= 1 then
      raise exception 'Last platform gestor';
    end if;
    delete from public.platform_gestors where user_id = p_user;
    delete from public.session_contexts where user_id = p_user and role = 'gestor';
  else
    -- Also serialize against platform revocations while checking the caller.
    lock table public.platform_gestors in share mode;
    lock table public.company_memberships in share row exclusive mode;
    if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
    if not exists (select 1 from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa') then
      raise exception 'Access unavailable';
    end if;
    if (select count(*) from public.company_memberships
      where company_id = p_company and role = 'empresa') <= 1 then
      raise exception 'Last company gestor';
    end if;
    delete from public.company_memberships
      where user_id = p_user and company_id = p_company and role = 'empresa';
    delete from public.session_contexts
      where user_id = p_user and company_id = p_company and role = 'empresa';
  end if;
  delete from public.membership_invites where lower(email) = (
    select lower(email) from public.profiles where id = p_user)
    and role = case when p_company is null then 'gestor' else 'empresa' end
    and company_id is not distinct from p_company;
  -- Identity, employee memberships, other companies and course authorship stay.
end $function$;

GRANT EXECUTE ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."revoke_gestor_access"(uuid, uuid) FROM PUBLIC, "anon", "service_role";
