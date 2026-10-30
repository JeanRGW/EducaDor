CREATE TABLE "public"."companies" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"        text                     NOT NULL,
  "cnpj"        text,
  "code_prefix" text                     NOT NULL DEFAULT 'EDU'::text,
  "responsible" text,
  "email"       text,
  "phone"       text,
  "address"     text,
  "city"        text,
  "state"       text,
  "field"       text,
  "active"      boolean                  NOT NULL DEFAULT true,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "companies_cnpj_key" UNIQUE (cnpj),
  CONSTRAINT "companies_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."companies"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "companies_delete" ON "public"."companies"
  FOR DELETE
  TO PUBLIC
  USING (public.is_gestor());

CREATE POLICY "companies_insert" ON "public"."companies"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (public.is_gestor());

CREATE POLICY "companies_select" ON "public"."companies"
  FOR SELECT
  TO PUBLIC
  USING ((public.is_gestor() OR (id = public.own_company_id())));

CREATE POLICY "companies_update" ON "public"."companies"
  FOR UPDATE
  TO "authenticated"
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."companies" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "service_role";

REVOKE ALL ON TABLE "public"."companies" FROM "anon";


REVOKE ALL ON TABLE "public"."companies" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."companies" TO "postgres";
