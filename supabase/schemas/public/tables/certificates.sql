CREATE TABLE "public"."certificates" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "course_id"  uuid                     NOT NULL,
  "code"       text                     NOT NULL,
  "issued_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "company_id" uuid                     NOT NULL,
  CONSTRAINT "certificates_code_key" UNIQUE (code),
  CONSTRAINT "certificates_pkey" PRIMARY KEY (id),
  CONSTRAINT "certificates_user_id_company_id_course_id_key" UNIQUE (user_id, company_id, course_id),
  CONSTRAINT "certificates_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT "certificates_course_id_fkey" FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE,
  CONSTRAINT "certificates_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."certificates"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "certificates_select" ON "public"."certificates"
  FOR SELECT
  TO "authenticated"
  USING
    ((public.is_gestor() OR ((company_id = public.own_company_id()) AND ((public.context_role() = 'empresa'::text) OR ((public.context_role() = 'funcionario'::text) AND (user_id =
    auth.uid()))))));

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."certificates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."certificates" TO "service_role";

REVOKE ALL ON TABLE "public"."certificates" FROM "anon";


REVOKE ALL ON TABLE "public"."certificates" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."certificates" TO "postgres";
