CREATE TABLE "public"."modules" (
  "id"        uuid    NOT NULL DEFAULT gen_random_uuid(),
  "course_id" uuid    NOT NULL,
  "title"     text    NOT NULL,
  "position"  integer NOT NULL DEFAULT 0,
  CONSTRAINT "modules_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE,
  CONSTRAINT "modules_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."modules"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "modules_select" ON "public"."modules"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR public.employee_can_access_course(course_id)));

CREATE POLICY "modules_write" ON "public"."modules"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."modules" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."modules" TO "service_role";

REVOKE ALL ON TABLE "public"."modules" FROM "anon";


REVOKE ALL ON TABLE "public"."modules" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."modules" TO "postgres";
