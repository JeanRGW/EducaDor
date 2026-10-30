CREATE VIEW "public"."completion_by_dept" AS  SELECT cm.company_id,
    cm.dept AS department,
    round(((100.0 * (count(*) FILTER (WHERE (lp.status = 'completed'::text)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct
   FROM ((((public.company_memberships cm
     JOIN public.courses c ON ((c.all_companies OR (EXISTS ( SELECT 1
           FROM public.assignments a
          WHERE ((a.course_id = c.id) AND (a.company_id = cm.company_id) AND a.released))))))
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     LEFT JOIN public.lesson_progress lp ON (((lp.lesson_id = l.id) AND (lp.user_id = cm.user_id) AND (lp.company_id = cm.company_id))))
  WHERE ((cm.role = 'funcionario'::text) AND (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (cm.company_id = public.own_company_id()))))
  GROUP BY cm.company_id, cm.dept;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_dept" TO "service_role";

REVOKE ALL ON TABLE "public"."completion_by_dept" FROM "anon";


REVOKE ALL ON TABLE "public"."completion_by_dept" FROM "authenticated";

GRANT SELECT ON TABLE "public"."completion_by_dept" TO "authenticated";

REVOKE ALL ON TABLE "public"."completion_by_dept" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."completion_by_dept" TO "postgres";
