SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.company_managers_page (
  p_company uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS TABLE (
    id        uuid,
    full_name text,
    email     text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id()), false) then
    raise exception 'Forbidden';
  end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select p.id, p.full_name, p.email from public.profiles p
  join public.company_memberships m on m.user_id = p.id
  where m.company_id = p_company and m.role = 'empresa'
    and (strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(p.email), lower(coalesce(p_search, ''))) > 0)
  order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

REVOKE ALL ON FUNCTION "public"."company_managers_page"(uuid, text, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.directory_pending_invites (
  p_role    text    DEFAULT NULL::text,
  p_company uuid    DEFAULT NULL::uuid,
  p_search  text    DEFAULT ''::text,
  p_offset  integer DEFAULT 0
)
  RETURNS TABLE (
    email        text,
    role         text,
    company_id   uuid,
    expires_at   timestamp with time zone,
    full_name    text,
    company_name text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor() or public.context_role() = 'empresa', false) then
    raise exception 'Forbidden';
  end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name, c.name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  left join public.companies c on c.id = mi.company_id
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
    and (p_role is null or mi.role = p_role)
    and (p_company is null or mi.company_id = p_company)
    and (strpos(lower(mi.email), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(coalesce(p.full_name, '')), lower(coalesce(p_search, ''))) > 0
      or strpos(lower(coalesce(c.name, '')), lower(coalesce(p_search, ''))) > 0)
  order by mi.created_at desc, mi.id limit 50 offset p_offset;
end $function$;

REVOKE ALL ON FUNCTION "public"."directory_pending_invites"(text, uuid, text, integer) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.platform_professionals_page (
  p_search text    DEFAULT ''::text,
  p_offset integer DEFAULT 0
)
  RETURNS TABLE (
    id        uuid,
    full_name text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.is_gestor(), false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 or length(coalesce(p_search, '')) > 200 then raise exception 'Invalid page'; end if;
  return query select p.id, p.full_name from public.profiles p
  join public.platform_gestors g on g.user_id = p.id
  where strpos(lower(p.full_name), lower(coalesce(p_search, ''))) > 0
  order by p.full_name, p.id limit 50 offset p_offset;
end $function$;

REVOKE ALL ON FUNCTION "public"."platform_professionals_page"(text, integer) FROM PUBLIC, "anon", "service_role";

GRANT EXECUTE ON FUNCTION "public"."company_managers_page"(uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."company_managers_page"(uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_managers_page"(uuid, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."directory_pending_invites"(text, uuid, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."directory_pending_invites"(text, uuid, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."directory_pending_invites"(text, uuid, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."platform_professionals_page"(text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."platform_professionals_page"(text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."platform_professionals_page"(text, integer) TO "postgres";
