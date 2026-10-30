CREATE TABLE "public"."membership_invites" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "email"      text                     NOT NULL,
  "role"       text                     NOT NULL,
  "company_id" uuid,
  "dept"       text,
  "job_title"  text,
  "invited_by" uuid,
  "token_hash" text                     NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "invite_scope" CHECK ((((role = 'gestor'::text) AND (company_id IS NULL)) OR ((role = ANY (ARRAY['empresa'::text, 'funcionario'::text])) AND (company_id IS
    NOT NULL)))),
  CONSTRAINT "membership_invites_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT "membership_invites_pkey" PRIMARY KEY (id),
  CONSTRAINT "membership_invites_role_check" CHECK ((role = ANY (ARRAY['gestor'::text, 'empresa'::text, 'funcionario'::text]))),
  CONSTRAINT "membership_invites_token_hash_check" CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "membership_invites_token_hash_key" UNIQUE (token_hash),
  CONSTRAINT "membership_invites_invited_by_fkey" FOREIGN KEY (invited_by) REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE "public"."membership_invites"
  ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX membership_invites_unique_pending ON public.membership_invites
  USING btree (lower(email), ROLE, COALESCE(company_id, '00000000-0000-0000-0000-000000000000'::uuid));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."membership_invites" TO "service_role";

REVOKE ALL ON TABLE "public"."membership_invites" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."membership_invites" TO "postgres";

REVOKE ALL ON TABLE "public"."membership_invites" FROM "anon", "authenticated";
