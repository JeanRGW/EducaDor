CREATE OR REPLACE FUNCTION public.employee_certificates (
  p_company uuid,
  p_offset  integer DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset is null or p_offset < 0 then raise exception 'Invalid query'; end if;
  select jsonb_build_object('total',(select count(*) from public.certificates where user_id = auth.uid() and company_id = p_company),
    'items',coalesce((select jsonb_agg(to_jsonb(p) order by issued_at desc,id) from (
      select ce.id, ce.code, ce.issued_at, ce.course_id, c.title as course_title,
        co.name as company_name, pr.full_name as employee_name
      from public.certificates ce join public.courses c on c.id = ce.course_id
      join public.companies co on co.id = ce.company_id join public.profiles pr on pr.id = ce.user_id
      where ce.user_id = auth.uid() and ce.company_id = p_company order by ce.issued_at desc,ce.id limit 50 offset p_offset
    ) p),'[]'::jsonb)) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."employee_certificates"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_certificates"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_certificates"(uuid, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_certificates"(uuid, integer) FROM PUBLIC, "anon", "service_role";
