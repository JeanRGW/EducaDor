CREATE VIEW "public"."completion_by_company" AS  SELECT co.id AS company_id,
    co.name AS company,
    round(((100.0 * (count(*) FILTER (WHERE (lp.status = 'completed'::text)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct
   FROM (((((public.companies co
     JOIN public.company_memberships cm ON (((cm.company_id = co.id) AND (cm.role = 'funcionario'::text))))
     JOIN public.courses c ON ((c.all_companies OR (EXISTS ( SELECT 1
           FROM public.assignments a
          WHERE ((a.course_id = c.id) AND (a.company_id = co.id) AND a.released))))))
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     LEFT JOIN public.lesson_progress lp ON (((lp.lesson_id = l.id) AND (lp.user_id = cm.user_id) AND (lp.company_id = co.id))))
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (co.id = public.own_company_id())))
  GROUP BY co.id;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_company" TO "service_role";

REVOKE ALL ON TABLE "public"."completion_by_company" FROM "anon";


REVOKE ALL ON TABLE "public"."completion_by_company" FROM "authenticated";

GRANT SELECT ON TABLE "public"."completion_by_company" TO "authenticated";

REVOKE ALL ON TABLE "public"."completion_by_company" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_company" TO "postgres";
