CREATE TABLE "public"."lessons" (
  "id"             uuid    NOT NULL DEFAULT gen_random_uuid(),
  "module_id"      uuid    NOT NULL,
  "title"          text    NOT NULL,
  "kind"           text    NOT NULL,
  "video_provider" text    NOT NULL DEFAULT 'youtube'::text,
  "video_id"       text,
  "file_key"       text,
  "points"         integer NOT NULL DEFAULT 10,
  "quiz_json"      jsonb,
  "position"       integer NOT NULL DEFAULT 0,
  "body"           text    NOT NULL DEFAULT ''::text,
  "image_keys"     text[]  NOT NULL DEFAULT '{}'::text[],
  "frame_ms"       integer NOT NULL DEFAULT 1000,
  CONSTRAINT "lessons_frame_ms_check" CHECK (((frame_ms >= 100) AND (frame_ms <= 10000))),
  CONSTRAINT "lessons_kind_check" CHECK ((kind = ANY (ARRAY['video'::text, 'audio'::text, 'pdf'::text, 'quiz'::text, 'reading'::text, 'animation'::text]))),
  CONSTRAINT "lessons_pkey" PRIMARY KEY (id),
  CONSTRAINT "lessons_video_provider_check" CHECK ((video_provider = 'youtube'::text)),
  CONSTRAINT "lessons_module_id_fkey" FOREIGN KEY (module_id) REFERENCES public.modules(id) ON DELETE CASCADE
);

ALTER TABLE "public"."lessons"
  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lessons_select" ON "public"."lessons"
  FOR SELECT
  TO "authenticated"
  USING ((public.is_gestor() OR (EXISTS ( SELECT 1
   FROM public.modules m
  WHERE ((m.id = lessons.module_id) AND public.employee_can_access_course(m.course_id))))));

CREATE POLICY "lessons_write" ON "public"."lessons"
  FOR ALL
  TO PUBLIC
  USING (public.is_gestor())
  WITH CHECK (public.is_gestor());

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."lessons" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lessons" TO "service_role";

REVOKE ALL ON TABLE "public"."lessons" FROM "anon";


REVOKE ALL ON TABLE "public"."lessons" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."lessons" TO "postgres";
