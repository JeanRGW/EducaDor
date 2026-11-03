CREATE TABLE "public"."redemptions" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"    uuid                     NOT NULL,
  "reward_id"  uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "company_id" uuid                     NOT NULL,
  CONSTRAINT "redemptions_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT "redemptions_pkey" PRIMARY KEY (id),
  CONSTRAINT "redemptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT "redemptions_reward_id_fkey" FOREIGN KEY (reward_id) REFERENCES public.rewards(id)
);

ALTER TABLE "public"."redemptions"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "redemptions_select" ON "public"."redemptions"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR ((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()))));

REVOKE DELETE, INSERT, UPDATE ON TABLE "public"."redemptions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."redemptions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."redemptions" TO "service_role";

REVOKE ALL ON TABLE "public"."redemptions" FROM "anon";


REVOKE ALL ON TABLE "public"."redemptions" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."redemptions" TO "postgres";
