-- Direct Storage API calls from a signed-in user must also use a live session.
CREATE POLICY "storage_public_session" ON "storage"."objects"
  AS RESTRICTIVE
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());

CREATE POLICY "storage_public_delete" ON "storage"."objects"
  FOR DELETE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND name ~ '^covers/[A-Za-z0-9_-]+[.]webp$' AND public.is_gestor()));

CREATE POLICY "storage_public_read" ON "storage"."objects"
  FOR SELECT
  TO PUBLIC
  USING ((bucket_id = 'educador-public'::text));

CREATE POLICY "storage_public_update" ON "storage"."objects"
  FOR UPDATE
  TO PUBLIC
  USING (((bucket_id = 'educador-public'::text) AND name ~ '^covers/[A-Za-z0-9_-]+[.]webp$' AND public.is_gestor()))
  WITH CHECK (((bucket_id = 'educador-public'::text) AND name ~ '^covers/[A-Za-z0-9_-]+[.]webp$' AND public.is_gestor()));

CREATE POLICY "storage_public_write" ON "storage"."objects"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((bucket_id = 'educador-public'::text) AND name ~ '^covers/[A-Za-z0-9_-]+[.]webp$' AND public.is_gestor()));
