CREATE OR REPLACE FUNCTION public.pending_invites_page (
  p_role    text DEFAULT NULL::text,
  p_company uuid DEFAULT NULL::uuid
)
  RETURNS TABLE (
    email        text,
    role         text,
    company_id   uuid,
    expires_at   timestamp with time zone,
    full_name    text,
    company_name text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name, c.name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  left join public.companies c on c.id = mi.company_id
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
    and (p_role is null or mi.role = p_role)
    and (p_company is null or mi.company_id = p_company)
  order by mi.created_at desc, mi.id limit 50
$function$;

GRANT EXECUTE ON FUNCTION "public"."pending_invites_page"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."pending_invites_page"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites_page"(text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."pending_invites_page"(text, uuid) FROM PUBLIC, "anon", "service_role";
