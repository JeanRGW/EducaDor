CREATE OR REPLACE FUNCTION public.employee_catalog (
  p_company uuid,
  p_search  text    DEFAULT ''::text,
  p_kind    text    DEFAULT NULL::text,
  p_state   text    DEFAULT NULL::text,
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
  if not coalesce(public.context_role()='funcionario' and p_company=public.own_company_id(),false) then raise exception 'Forbidden'; end if;
  if p_offset<0 or p_offset is null or (p_kind is not null and p_kind not in ('video','audio','pdf','quiz','reading','animation'))
    or (p_state is not null and p_state not in ('not_started','in_progress','completed')) then raise exception 'Invalid query'; end if;
  with catalog as (
    select c.id,c.title,c.description,c.cover_key,count(l.id)::int as lesson_count,
      count(l.id) filter(where lp.status='completed')::int as completed_count,max(lp.updated_at) as last_activity_at,
      case when count(l.id)>0 and count(l.id)=count(l.id) filter(where lp.status='completed') then 'completed'
        when count(lp.lesson_id)>0 then 'in_progress' else 'not_started' end as state
    from public.courses c left join public.modules m on m.course_id=c.id left join public.lessons l on l.module_id=m.id
    left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=auth.uid() and lp.company_id=p_company
    where public.employee_can_access_course(c.id) and strpos(lower(c.title),lower(trim(coalesce(p_search,''))))>0
      and (p_kind is null or exists(select 1 from public.modules fm join public.lessons fl on fl.module_id=fm.id where fm.course_id=c.id and fl.kind=p_kind))
    group by c.id
  ), matching as (select * from catalog where p_state is null or state=p_state), page as (
    select * from matching order by last_activity_at desc nulls last,lower(title),id limit 50 offset p_offset
  ) select jsonb_build_object('total',(select count(*) from matching),'items',coalesce((select jsonb_agg(to_jsonb(p) order by last_activity_at desc nulls last,lower(title),id) from page p),'[]'::jsonb)) into result;
  return result;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."employee_catalog"(uuid, text, text, text, integer) FROM PUBLIC, "anon", "service_role";
