CREATE OR REPLACE FUNCTION public.content_catalog (
  p_search text    DEFAULT ''::text,
  p_kind   text    DEFAULT NULL::text,
  p_offset integer DEFAULT 0,
  p_limit  integer DEFAULT 50
)
  RETURNS TABLE (
    id               uuid,
    title            text,
    kind             text,
    description      text,
    cover_key        text,
    platform_enabled boolean,
    all_companies    boolean,
    company_enabled  boolean,
    company_ids      uuid[],
    company_count    bigint,
    lesson_count     bigint,
    completion_pct   numeric,
    module_count     bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare cid uuid := public.own_company_id(); platform boolean := coalesce(public.is_gestor(), false);
begin
  if not platform and (public.context_role() is distinct from 'empresa' or cid is null) then raise exception 'Forbidden'; end if;
  return query with page as (
    select c.* from public.courses c where (platform or public.course_company_allowed(c.id,cid))
      and (p_kind is null or p_kind='course' or exists(select 1 from public.modules m join public.lessons l on l.module_id=m.id where m.course_id=c.id and l.kind=p_kind))
      and (coalesce(p_search,'')='' or strpos(lower(c.title),lower(p_search))>0)
    order by c.created_at desc,c.id limit least(greatest(coalesce(p_limit,50),1),50) offset greatest(coalesce(p_offset,0),0)
  ) select c.id,c.title,c.kind,c.description,c.cover_key,c.status='released',c.all_companies,
    case when platform then true else coalesce((select a.company_enabled from public.assignments a where a.course_id=c.id and a.company_id=cid),true) end,
    case when platform then array(select a.company_id from public.assignments a where a.course_id=c.id and a.released order by a.company_id) else null::uuid[] end,
    case when platform then (select count(*) from public.companies co where co.active and public.course_company_allowed(c.id,co.id)) else 1::bigint end,
    (select count(*) from public.lessons l join public.modules m on m.id=l.module_id where m.course_id=c.id),
    (select round(100.0*count(*) filter(where lp.status='completed')/nullif(count(*),0),1)
      from public.modules m join public.lessons l on l.module_id=m.id
      join public.company_memberships cm on cm.role='funcionario' join public.companies co on co.id=cm.company_id and co.active
      left join public.lesson_progress lp on lp.lesson_id=l.id and lp.user_id=cm.user_id and lp.company_id=cm.company_id
      where m.course_id=c.id and public.course_company_allowed(c.id,cm.company_id) and (platform or cm.company_id=cid)),
    (select count(*) from public.modules m where m.course_id=c.id)
  from page c order by c.created_at desc,c.id;
end $function$;

GRANT EXECUTE ON FUNCTION "public"."content_catalog"(text, text, integer, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."content_catalog"(text, text, integer, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."content_catalog"(text, text, integer, integer) TO "postgres";

REVOKE ALL ON FUNCTION "public"."content_catalog"(text, text, integer, integer) FROM PUBLIC, "anon", "service_role";
