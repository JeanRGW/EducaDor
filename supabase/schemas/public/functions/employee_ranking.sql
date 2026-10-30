CREATE OR REPLACE FUNCTION public.employee_ranking (
  p_company uuid
)
  RETURNS TABLE (
    user_id   uuid,
    full_name text,
    dept      text,
    points    bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role() = 'funcionario' and p_company = public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  return query select cm.user_id,p.full_name,cm.dept,
    coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id where lp.user_id = cm.user_id and lp.company_id = p_company and lp.status = 'completed'),0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id where d.user_id = cm.user_id and d.company_id = p_company),0)
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario' order by 4 desc,lower(p.full_name),cm.user_id limit 3;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."employee_ranking"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_ranking"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_ranking"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_ranking"(uuid) FROM PUBLIC, "anon", "service_role";
