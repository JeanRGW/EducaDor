-- Presentation only: callers enforce access before resolving a version.
CREATE OR REPLACE FUNCTION public.resolved_lesson_content(p_lesson public.lessons, p_gender text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO '' AS $function$
  SELECT CASE WHEN p_lesson.alternate_content IS NOT NULL
      AND p_gender IS NOT NULL AND p_gender <> p_lesson.content_gender
    THEN (to_jsonb(p_lesson) - 'alternate_content') || jsonb_build_object(
      'content_gender', p_gender,
      'video_id', p_lesson.alternate_content->'video_id',
      'file_key', p_lesson.alternate_content->'file_key',
      'image_keys', coalesce(p_lesson.alternate_content->'image_keys','[]'::jsonb),
      'frame_ms', coalesce(p_lesson.alternate_content->'frame_ms','1000'::jsonb),
      'body', coalesce(p_lesson.alternate_content->'body','""'::jsonb),
      'quiz_json', p_lesson.alternate_content->'questions')
    ELSE to_jsonb(p_lesson) - 'alternate_content' END;
$function$;
REVOKE ALL ON FUNCTION public.resolved_lesson_content(public.lessons, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolved_lesson_content(public.lessons, text) TO postgres;
