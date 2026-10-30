CREATE TABLE "public"."fcm_tokens" (
  "user_id"    uuid                     NOT NULL,
  "token"      text                     NOT NULL,
  "platform"   text                     NOT NULL DEFAULT 'android'::text,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "fcm_tokens_pkey" PRIMARY KEY (user_id, token),
  CONSTRAINT "fcm_tokens_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."fcm_tokens"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fcm_tokens_all" ON "public"."fcm_tokens"
  FOR ALL
  TO "authenticated"
  USING ((user_id = auth.uid()))
  WITH CHECK ((user_id = auth.uid()));

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."fcm_tokens" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."fcm_tokens" TO "service_role";

REVOKE ALL ON TABLE "public"."fcm_tokens" FROM "anon";


REVOKE ALL ON TABLE "public"."fcm_tokens" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."fcm_tokens" TO "postgres";
