CREATE OR REPLACE FUNCTION public.company_completion_export (
  p_company uuid,
  p_after   uuid DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result jsonb;
begin
  if not coalesce(public.is_gestor() or
    (public.context_role() = 'empresa' and p_company = public.own_company_id()), false) then
    raise exception 'Forbidden';
  end if;
  with page as (
    select cm.user_id, p.full_name, p.email, cm.dept, cm.job_title
    from public.company_memberships cm
    join public.profiles p on p.id = cm.user_id
    where cm.company_id = p_company and cm.role = 'funcionario'
      and (p_after is null or cm.user_id > p_after)
    order by cm.user_id
    limit 50
  ), items as (
    select p.*,
      (select round(100.0 * count(l.id) filter (where lp.status = 'completed') /
        nullif(count(l.id), 0), 1)
        from public.courses c
        join public.modules m on m.course_id = c.id
        join public.lessons l on l.module_id = m.id
        left join public.lesson_progress lp on lp.lesson_id = l.id
          and lp.user_id = p.user_id and lp.company_id = p_company
        where public.course_company_allowed(c.id, p_company)) as pct
    from page p
  )
  select jsonb_build_object(
    'total_count', (select count(*) from public.company_memberships cm
      where cm.company_id = p_company and cm.role = 'funcionario'),
    'items', coalesce((select jsonb_agg(to_jsonb(i) order by user_id)
      from items i), '[]'::jsonb)
  ) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."company_completion_export"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."company_completion_export"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."company_completion_export"(uuid, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."company_completion_export"(uuid, uuid) FROM PUBLIC, "anon", "service_role";
