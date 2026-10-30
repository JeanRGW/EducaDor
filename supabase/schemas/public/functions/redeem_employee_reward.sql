CREATE OR REPLACE FUNCTION public.redeem_employee_reward (
  p_company uuid,
  p_reward  uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id=sc.user_id and cm.company_id=sc.company_id and cm.role=sc.role
    join public.companies co on co.id=cm.company_id and co.active
    where sc.user_id=auth.uid() and sc.session_id=nullif(auth.jwt()->>'session_id','')::uuid and sc.role='funcionario' and sc.company_id=p_company
    for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform public.redeem_reward(p_reward);
end $function$;

GRANT EXECUTE ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."redeem_employee_reward"(uuid, uuid) FROM PUBLIC, "anon", "service_role";
