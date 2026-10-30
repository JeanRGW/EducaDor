CREATE VIEW "public"."popular_content" AS  SELECT lp.company_id,
    c.title AS course,
    count(*) FILTER (WHERE (lp.status = 'completed'::text)) AS completions
   FROM (((public.courses c
     JOIN public.modules m ON ((m.course_id = c.id)))
     JOIN public.lessons l ON ((l.module_id = m.id)))
     JOIN public.lesson_progress lp ON ((lp.lesson_id = l.id)))
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (lp.company_id = public.own_company_id())))
  GROUP BY lp.company_id, c.title;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."popular_content" TO "service_role";

REVOKE ALL ON TABLE "public"."popular_content" FROM "anon";


REVOKE ALL ON TABLE "public"."popular_content" FROM "authenticated";

GRANT SELECT ON TABLE "public"."popular_content" TO "authenticated";

REVOKE ALL ON TABLE "public"."popular_content" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."popular_content" TO "postgres";
