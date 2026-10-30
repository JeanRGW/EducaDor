CREATE OR REPLACE FUNCTION public.pending_invites()
  RETURNS TABLE (
    email      text,
    role       text,
    company_id uuid,
    expires_at timestamp with time zone,
    full_name  text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select mi.email, mi.role, mi.company_id, mi.expires_at, p.full_name
  from public.membership_invites mi
  left join public.profiles p on lower(p.email) = lower(mi.email)
  where mi.expires_at > now()
    and (public.is_gestor() or
      (public.context_role() = 'empresa' and mi.company_id = public.own_company_id()))
  order by mi.created_at desc limit 50
$function$;

GRANT EXECUTE ON FUNCTION "public"."pending_invites"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."pending_invites"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."pending_invites"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."pending_invites"() FROM PUBLIC, "anon", "service_role";
