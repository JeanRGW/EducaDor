CREATE OR REPLACE FUNCTION public.issue_employee_certificate (
  p_user    uuid,
  p_session uuid,
  p_company uuid,
  p_course  uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare result uuid; prefix text; code_value text;
begin
  perform pg_advisory_xact_lock(hashtext(p_user::text || p_company::text || p_course::text));
  perform 1 from public.session_contexts sc join public.company_memberships cm on cm.user_id = sc.user_id and cm.company_id = sc.company_id and cm.role = sc.role
    join public.companies co on co.id = cm.company_id and co.active
    where sc.user_id = p_user and sc.session_id = p_session and sc.role = 'funcionario' and sc.company_id = p_company for share of sc,cm,co;
  if not found then raise exception 'Forbidden'; end if;
  perform 1 from public.courses c where c.id = p_course and c.status = 'released' and public.course_company_allowed(c.id,p_company)
    and coalesce((select company_enabled from public.assignments a where a.course_id = c.id and a.company_id = p_company),true) for share;
  if not found then raise exception 'Course unavailable'; end if;
  if not exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id where m.course_id = p_course)
    or exists(select 1 from public.lessons l join public.modules m on m.id = l.module_id
      left join public.lesson_progress lp on lp.lesson_id = l.id and lp.user_id = p_user and lp.company_id = p_company
      where m.course_id = p_course and lp.status is distinct from 'completed') then raise exception 'Course incomplete'; end if;
  select id into result from public.certificates where user_id = p_user and company_id = p_company and course_id = p_course;
  if found then return result; end if;
  select co.code_prefix into prefix from public.companies co where co.id = p_company;
  for attempt in 1..10 loop
    code_value := prefix || '-';
    for digit in 1..6 loop code_value := code_value || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ',1+floor(random()*32)::int,1); end loop;
    begin
      insert into public.certificates(user_id,company_id,course_id,code) values(p_user,p_company,p_course,code_value) returning id into result;
      return result;
    exception when unique_violation then null;
    end;
  end loop;
  raise exception 'Certificate code unavailable';
end $function$;

GRANT EXECUTE ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) TO "postgres";

REVOKE ALL ON FUNCTION "public"."issue_employee_certificate"(uuid, uuid, uuid, uuid) FROM PUBLIC, "anon", "authenticated";
