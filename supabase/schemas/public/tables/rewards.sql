CREATE TABLE "public"."rewards" (
  "id"          uuid    NOT NULL DEFAULT gen_random_uuid(),
  "title"       text    NOT NULL,
  "points_cost" integer NOT NULL,
  "active"      boolean NOT NULL DEFAULT true,
  CONSTRAINT "rewards_pkey" PRIMARY KEY (id),
  CONSTRAINT "rewards_points_cost_check" CHECK ((points_cost > 0))
);

ALTER TABLE "public"."rewards"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rewards_select" ON "public"."rewards"
  FOR SELECT
  TO "authenticated"
  USING ((active AND (public.is_gestor() OR (public.context_role() = 'funcionario'::text))));

CREATE POLICY "rewards_write" ON "public"."rewards"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."rewards" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."rewards" TO "service_role";

REVOKE ALL ON TABLE "public"."rewards" FROM "anon";


REVOKE ALL ON TABLE "public"."rewards" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."rewards" TO "postgres";
