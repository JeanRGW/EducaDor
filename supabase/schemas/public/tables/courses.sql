CREATE TABLE "public"."courses" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "title"          text                     NOT NULL,
  "kind"           text                     NOT NULL DEFAULT 'course'::text,
  "cover_key"      text,
  "description"    text,
  "status"         text                     NOT NULL DEFAULT 'released'::text,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "all_companies"  boolean                  NOT NULL DEFAULT true,
  "responsible_id" uuid,
  "push_pending_at" timestamp with time zone,
  "push_claimed_at" timestamp with time zone,
  CONSTRAINT "courses_pkey" PRIMARY KEY (id),
  CONSTRAINT "courses_created_by_fkey" FOREIGN KEY (created_by) REFERENCES public.profiles(id),
  CONSTRAINT "courses_responsible_id_fkey" FOREIGN KEY (responsible_id) REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE "public"."courses"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "courses_select" ON "public"."courses"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR public.employee_can_access_course(id)));

CREATE POLICY "courses_write" ON "public"."courses"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, SELECT ON TABLE "public"."courses" TO "authenticated";
GRANT INSERT (id, title, kind, cover_key, description, status, created_by, created_at, all_companies, responsible_id),
  UPDATE (id, title, kind, cover_key, description, status, created_by, created_at, all_companies, responsible_id)
  ON TABLE "public"."courses" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."courses" TO "service_role";

REVOKE ALL ON TABLE "public"."courses" FROM "anon";


REVOKE ALL ON TABLE "public"."courses" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."courses" TO "postgres";
