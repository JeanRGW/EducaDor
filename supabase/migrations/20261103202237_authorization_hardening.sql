SET local check_function_bodies = off;

REVOKE ALL ("address") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("avatar_key") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("birth_date") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("needs_password") ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("phone") ON TABLE "public"."profiles" FROM "authenticated";

DROP POLICY "profiles_update" ON "public"."profiles";

DROP POLICY "storage_public_delete" ON "storage"."objects";

DROP POLICY "storage_public_update" ON "storage"."objects";

DROP POLICY "storage_public_write" ON "storage"."objects";

CREATE OR REPLACE FUNCTION public.complete_password_setup()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.uid() is null then raise exception 'Forbidden'; end if;
  -- Match Auth's HasPassword semantics; this is onboarding state, not reauthentication.
  perform 1 from auth.users where id = auth.uid()
    and coalesce(encrypted_password, '') <> '' for share;
  if not found then raise exception 'Password unavailable'; end if;
  update public.profiles set needs_password = false where id = auth.uid();
  if not found then raise exception 'Profile unavailable'; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."complete_password_setup"() FROM PUBLIC, "anon", "service_role";

CREATE POLICY "storage_public_delete" ON "storage"."objects"
  FOR DELETE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND (name ~ '^covers/[A-Za-z0-9_-]+[.]webp$'::text) AND public.is_gestor()));

CREATE POLICY "storage_public_update" ON "storage"."objects"
  FOR UPDATE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND (name ~ '^covers/[A-Za-z0-9_-]+[.]webp$'::text) AND public.is_gestor()))
  WITH CHECK (((bucket_id = 'educador-public'::text) AND (name ~ '^covers/[A-Za-z0-9_-]+[.]webp$'::text) AND public.is_gestor()));

CREATE POLICY "storage_public_write" ON "storage"."objects"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((bucket_id = 'educador-public'::text) AND (name ~ '^covers/[A-Za-z0-9_-]+[.]webp$'::text) AND public.is_gestor()));

GRANT EXECUTE ON FUNCTION "public"."complete_password_setup"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."complete_password_setup"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."complete_password_setup"() TO "postgres";

REVOKE ALL ON TABLE "public"."certificates" FROM "authenticated";

GRANT SELECT ON TABLE "public"."certificates" TO "authenticated";

REVOKE ALL ON TABLE "public"."lesson_progress" FROM "authenticated";

GRANT DELETE, SELECT ON TABLE "public"."lesson_progress" TO "authenticated";

REVOKE ALL ON TABLE "public"."redemptions" FROM "authenticated";

GRANT SELECT ON TABLE "public"."redemptions" TO "authenticated";
