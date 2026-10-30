CREATE TABLE "public"."platform_gestors" (
  "user_id" uuid NOT NULL,
  CONSTRAINT "platform_gestors_pkey" PRIMARY KEY (user_id),
  CONSTRAINT "platform_gestors_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."platform_gestors"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "platform_gestors_select" ON "public"."platform_gestors"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR public.is_gestor()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."platform_gestors" TO "service_role";

REVOKE ALL ON TABLE "public"."platform_gestors" FROM "anon";


REVOKE ALL ON TABLE "public"."platform_gestors" FROM "authenticated";

GRANT SELECT ON TABLE "public"."platform_gestors" TO "authenticated";

REVOKE ALL ON TABLE "public"."platform_gestors" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."platform_gestors" TO "postgres";
