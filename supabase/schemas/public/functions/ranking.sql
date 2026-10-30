CREATE OR REPLACE FUNCTION public.ranking (
  p_company uuid,
  p_limit   integer DEFAULT 20
)
  RETURNS TABLE (
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
  if not coalesce(public.is_gestor() or (public.context_role() in ('empresa', 'funcionario')
    and p_company = public.own_company_id()), false) then raise exception 'Forbidden'; end if;
  return query select p.full_name, cm.dept,
    (coalesce((select sum(l.points) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      where lp.user_id = p.id and lp.company_id = p_company and lp.status = 'completed'), 0)
    - coalesce((select sum(r.points_cost) from public.redemptions d join public.rewards r on r.id = d.reward_id
      where d.user_id = p.id and d.company_id = p_company), 0))::bigint
  from public.company_memberships cm join public.profiles p on p.id = cm.user_id
  where cm.company_id = p_company and cm.role = 'funcionario'
  order by 3 desc, lower(p.full_name), p.id limit least(greatest(coalesce(p_limit,20),1),100);
end $function$;

GRANT EXECUTE ON FUNCTION "public"."ranking"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."ranking"(uuid, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."ranking"(uuid, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."ranking"(uuid, integer) FROM PUBLIC, "anon", "service_role";
