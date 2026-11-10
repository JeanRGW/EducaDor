CREATE TABLE "public"."lesson_progress" (
  "user_id"      uuid                     NOT NULL,
  "lesson_id"    uuid                     NOT NULL,
  "status"       text                     NOT NULL DEFAULT 'in_progress'::text,
  "score"        integer,
  "position_sec" integer                  NOT NULL DEFAULT 0,
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "company_id"   uuid                     NOT NULL,
  "content_gender" text,
  CONSTRAINT "lesson_progress_content_gender_check" CHECK (content_gender IN ('male', 'female')),
  CONSTRAINT "lesson_progress_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT "lesson_progress_pkey" PRIMARY KEY (user_id, company_id, lesson_id),
  CONSTRAINT "lesson_progress_status_check" CHECK ((status = ANY (ARRAY['locked'::text, 'in_progress'::text, 'completed'::text]))),
  CONSTRAINT "lesson_progress_lesson_id_fkey" FOREIGN KEY (lesson_id) REFERENCES public.lessons(id) ON DELETE CASCADE,
  CONSTRAINT "lesson_progress_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."lesson_progress"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."lesson_progress"
  ADD CONSTRAINT "progress_nonnegative_position" CHECK ((position_sec >= 0)) NOT VALID;

CREATE INDEX lesson_progress_updated_at_idx ON public.lesson_progress USING btree (updated_at);

CREATE POLICY "progress_delete" ON "public"."lesson_progress"
  FOR DELETE
  TO "authenticated"
  USING (public.is_gestor());

CREATE POLICY "progress_insert" ON "public"."lesson_progress"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "progress_select" ON "public"."lesson_progress"
  FOR SELECT
  TO "authenticated"
  USING
    ((public.is_gestor() OR ((company_id = public.own_company_id()) AND ((public.context_role() = 'empresa'::text) OR ((public.context_role() = 'funcionario'::text) AND (user_id =
    auth.uid()))))));

CREATE POLICY "progress_update" ON "public"."lesson_progress"
  FOR UPDATE
  TO "authenticated"
  USING (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))))
  WITH CHECK (((public.context_role() = 'funcionario'::text) AND (user_id = auth.uid()) AND (company_id = public.own_company_id()) AND (EXISTS ( SELECT 1
   FROM (public.lessons l
     JOIN public.modules m ON ((m.id = l.module_id)))
  WHERE ((l.id = lesson_progress.lesson_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "progress_valid_insert" ON "public"."lesson_progress"
  AS RESTRICTIVE
  FOR INSERT
  TO "authenticated"
  WITH CHECK (public.employee_progress_valid(lesson_id, status));

CREATE POLICY "progress_valid_update" ON "public"."lesson_progress"
  AS RESTRICTIVE
  FOR UPDATE
  TO "authenticated"
  WITH CHECK (public.employee_progress_valid(lesson_id, status));

REVOKE INSERT, UPDATE ON TABLE "public"."lesson_progress" FROM "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."lesson_progress" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lesson_progress" TO "service_role";

REVOKE ALL ON TABLE "public"."lesson_progress" FROM "anon";


REVOKE ALL ON TABLE "public"."lesson_progress" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lesson_progress" TO "postgres";
