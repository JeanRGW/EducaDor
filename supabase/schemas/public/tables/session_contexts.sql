CREATE TABLE "public"."session_contexts" (
  "session_id" uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "role"       text                     NOT NULL,
  "company_id" uuid,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "context_scope" CHECK ((((role = 'gestor'::text) AND (company_id IS NULL)) OR ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text])) AND (company_id IS
    NOT NULL)))),
  CONSTRAINT "session_contexts_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT "session_contexts_pkey" PRIMARY KEY (session_id),
  CONSTRAINT "session_contexts_role_check" CHECK ((role = ANY (ARRAY['gestor'::text, 'empresa'::text, 'funcionario'::text]))),
  CONSTRAINT "session_contexts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."session_contexts"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX session_contexts_user_id_idx ON public.session_contexts USING btree (user_id);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."session_contexts" TO "service_role";

REVOKE ALL ON TABLE "public"."session_contexts" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."session_contexts" TO "postgres";

REVOKE ALL ON TABLE "public"."session_contexts" FROM "anon", "authenticated";
