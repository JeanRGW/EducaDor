CREATE OR REPLACE FUNCTION public.employee_completion (
  p_company uuid
)
  RETURNS TABLE (
    user_id   uuid,
    full_name text,
    email     text,
    dept      text,
    job_title text,
    pct       numeric
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
  return query
  select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title,
    round(100.0 * count(l.id) filter (where lp.status = 'completed') / nullif(count(l.id), 0), 1)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  left join public.courses c on public.course_company_allowed(c.id, cm.company_id)
  left join public.modules m on m.course_id = c.id
  left join public.lessons l on l.module_id = m.id
  left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = cm.user_id
    and lp.company_id = cm.company_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  group by cm.user_id, p.id, cm.dept, cm.job_title
  order by p.full_name limit 50;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."employee_completion"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_completion"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_completion"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_completion"(uuid) FROM PUBLIC, "anon", "service_role";
