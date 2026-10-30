CREATE OR REPLACE FUNCTION public.redeem_reward (
  p_reward uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare cost int; earned int; spent int; cid uuid := public.own_company_id();
begin
  if public.context_role() <> 'funcionario' or cid is null then
    raise exception 'Employee context required';
  end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text || cid::text));
  select points_cost into cost from public.rewards where id = p_reward and active;
  if not found then raise exception 'Reward unavailable'; end if;
  select coalesce(sum(l.points), 0) into earned from public.lesson_progress lp
    join public.lessons l on l.id = lp.lesson_id
    where lp.user_id = auth.uid() and lp.company_id = cid and lp.status = 'completed';
  select coalesce(sum(r.points_cost), 0) into spent from public.redemptions d
    join public.rewards r on r.id = d.reward_id
    where d.user_id = auth.uid() and d.company_id = cid;
  if earned - spent < cost then raise exception 'Insufficient points'; end if;
  insert into public.redemptions(user_id, company_id, reward_id)
  values (auth.uid(), cid, p_reward);
end $function$;

GRANT EXECUTE ON FUNCTION "public"."redeem_reward"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."redeem_reward"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."redeem_reward"(uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."redeem_reward"(uuid) FROM PUBLIC, "anon", "service_role";
