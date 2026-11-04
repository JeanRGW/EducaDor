CREATE POLICY mfa_profiles ON public.profiles AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY mfa_memberships ON public.company_memberships AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY mfa_gestors ON public.platform_gestors AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY mfa_fcm ON public.fcm_tokens AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
