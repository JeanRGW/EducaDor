CREATE TABLE "public"."assignments" (
  "course_id"       uuid    NOT NULL,
  "company_id"      uuid    NOT NULL,
  "released"        boolean NOT NULL DEFAULT true,
  "company_enabled" boolean NOT NULL DEFAULT true,
  CONSTRAINT "assignments_pkey" PRIMARY KEY (course_id, company_id),
  CONSTRAINT "assignments_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT "assignments_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE
);

ALTER TABLE "public"."assignments"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "assignments_select" ON "public"."assignments"
  FOR SELECT
  TO PUBLIC
  USING ((public.is_gestor() OR (company_id = public.own_company_id())));

CREATE POLICY "assignments_write" ON "public"."assignments"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."assignments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."assignments" TO "service_role";

REVOKE ALL ON TABLE "public"."assignments" FROM "anon";


REVOKE ALL ON TABLE "public"."assignments" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."assignments" TO "postgres";
