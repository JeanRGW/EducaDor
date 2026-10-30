CREATE VIEW "public"."engagement_monthly" AS  SELECT company_id,
    (date_trunc('month'::text, updated_at))::date AS month,
    count(DISTINCT user_id) AS active_users,
    count(*) AS events
   FROM public.lesson_progress
  WHERE (public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (company_id = public.own_company_id())))
  GROUP BY company_id, ((date_trunc('month'::text, updated_at))::date);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engagement_monthly" TO "service_role";

REVOKE ALL ON TABLE "public"."engagement_monthly" FROM "anon";


REVOKE ALL ON TABLE "public"."engagement_monthly" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engagement_monthly" TO "authenticated";

REVOKE ALL ON TABLE "public"."engagement_monthly" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engagement_monthly" TO "postgres";
