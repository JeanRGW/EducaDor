CREATE POLICY "mfa_notification_preferences" ON "public"."notification_preferences"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (public.mfa_access_allowed())
  WITH CHECK (public.mfa_access_allowed());
