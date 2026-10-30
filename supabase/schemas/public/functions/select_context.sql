CREATE OR REPLACE FUNCTION public.select_context (
  p_role       text,
  p_company_id uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare sid uuid := nullif(auth.jwt()->>'session_id', '')::uuid;
begin
  if auth.uid() is null or sid is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.available_contexts() ac
    where ac.role = p_role and ac.company_id is not distinct from p_company_id) then
    raise exception 'Context unavailable';
  end if;
  insert into public.session_contexts(session_id, user_id, role, company_id)
  values (sid, auth.uid(), p_role, p_company_id)
  on conflict (session_id) do update set role = excluded.role,
    company_id = excluded.company_id, updated_at = now()
  where session_contexts.user_id = excluded.user_id;
  if not found then raise exception 'Session mismatch'; end if;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."select_context"(text, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."select_context"(text, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."select_context"(text, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."select_context"(text, uuid) FROM PUBLIC, "anon", "service_role";
