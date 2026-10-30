CREATE TABLE "public"."company_memberships" (
  "user_id"    uuid NOT NULL,
  "company_id" uuid NOT NULL,
  "role"       text NOT NULL,
  "dept"       text,
  "job_title"  text,
  CONSTRAINT "company_memberships_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT "company_memberships_pkey" PRIMARY KEY (user_id, company_id, ROLE),
  CONSTRAINT "company_memberships_role_check" CHECK ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text]))),
  CONSTRAINT "company_memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."company_memberships"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX company_memberships_company_role_idx ON public.company_memberships USING btree (company_id, ROLE);

CREATE POLICY "company_memberships_select" ON "public"."company_memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (company_id = public.own_company_id()))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."company_memberships" TO "service_role";

REVOKE ALL ON TABLE "public"."company_memberships" FROM "anon";


REVOKE ALL ON TABLE "public"."company_memberships" FROM "authenticated";

GRANT SELECT ON TABLE "public"."company_memberships" TO "authenticated";

REVOKE ALL ON TABLE "public"."company_memberships" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."company_memberships" TO "postgres";
