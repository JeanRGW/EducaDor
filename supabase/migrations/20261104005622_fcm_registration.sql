SET local check_function_bodies = off;

DROP POLICY "fcm_tokens_all" ON "public"."fcm_tokens";

CREATE TABLE "public"."notification_preferences" (
  "user_id"      uuid    NOT NULL,
  "push_enabled" boolean NOT NULL DEFAULT true,
  CONSTRAINT "notification_preferences_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."notification_preferences"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."notification_preferences" FROM "anon";

CREATE OR REPLACE FUNCTION public.register_fcm_token (
  p_token    text,
  p_platform text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_token is null or length(p_token) not between 1 and 4096 or
    p_token <> trim(p_token) or p_platform not in ('android', 'ios', 'web') or p_platform is null then
    raise exception 'Invalid token';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_token, 0));
  delete from public.fcm_tokens where token = p_token and user_id <> auth.uid();
  insert into public.fcm_tokens(user_id, token, platform, updated_at)
    values (auth.uid(), p_token, p_platform, now())
    on conflict (user_id, token) do update set platform = excluded.platform, updated_at = excluded.updated_at;
end $function$;

REVOKE ALL ON FUNCTION "public"."register_fcm_token"(text, text) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.set_push_enabled (
  p_enabled boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_enabled is null then raise exception 'Invalid preference'; end if;
  insert into public.notification_preferences(user_id, push_enabled)
    values (auth.uid(), p_enabled)
    on conflict (user_id) do update set push_enabled = excluded.push_enabled;
end $function$;

REVOKE ALL ON FUNCTION "public"."set_push_enabled"(boolean) FROM PUBLIC, "anon", "service_role";

CREATE OR REPLACE FUNCTION public.unregister_fcm_token (
  p_token text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform public.context_role();
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  if p_token is null or length(p_token) not between 1 and 4096 then raise exception 'Invalid token'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_token, 0));
  delete from public.fcm_tokens where user_id = auth.uid() and token = p_token;
end $function$;

REVOKE ALL ON FUNCTION "public"."unregister_fcm_token"(text) FROM PUBLIC, "anon", "service_role";

ALTER TABLE "public"."notification_preferences"
  ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

CREATE POLICY "fcm_tokens_select" ON "public"."fcm_tokens"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = auth.uid()));

CREATE POLICY "notification_preferences_select" ON "public"."notification_preferences"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = auth.uid()));

GRANT EXECUTE ON FUNCTION "public"."register_fcm_token"(text, text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."register_fcm_token"(text, text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."register_fcm_token"(text, text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_push_enabled"(boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_push_enabled"(boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_push_enabled"(boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."unregister_fcm_token"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."unregister_fcm_token"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."unregister_fcm_token"(text) TO "postgres";

REVOKE ALL ON TABLE "public"."fcm_tokens" FROM "authenticated";

GRANT SELECT ON TABLE "public"."fcm_tokens" TO "authenticated";

REVOKE ALL ON TABLE "public"."notification_preferences" FROM "authenticated";

GRANT SELECT ON TABLE "public"."notification_preferences" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."notification_preferences" TO "service_role";
