CREATE TABLE "public"."profiles" (
  "id"             uuid    NOT NULL,
  "full_name"      text    NOT NULL,
  "email"          text    NOT NULL,
  "avatar_key"     text,
  "phone"          text,
  "birth_date"     date,
  "address"        text,
  "gender"         text,
  CONSTRAINT "profiles_gender_check" CHECK (gender IN ('male', 'female')),
  "needs_password" boolean NOT NULL DEFAULT false,
  CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX profiles_email_ci ON public.profiles USING btree (lower(email));

CREATE POLICY "profiles_select" ON "public"."profiles"
  FOR SELECT
  TO "authenticated"
  USING (((id = auth.uid()) OR public.is_gestor() OR ((public.context_role() = 'empresa'::text) AND (EXISTS ( SELECT 1
   FROM public.company_memberships cm
  WHERE ((cm.user_id = profiles.id) AND (cm.company_id = public.own_company_id())))))));

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";


REVOKE ALL ("address") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("avatar_key") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("birth_date") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("needs_password") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("phone") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";
