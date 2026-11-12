-- Restrictive session gate for every direct authenticated table access.
-- These policies coexist with each table's normal policies (permissive OR +
-- restrictive AND), so a revoked session cannot read or write even where a
-- policy only checks auth.uid() or the selected context. service_role bypasses
-- RLS as before; the privileged RPCs revalidate the session themselves.
CREATE POLICY session_live_assignments ON public.assignments AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_certificates ON public.certificates AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
-- profiles, company_memberships, platform_gestors, fcm_tokens and
-- notification_preferences already have a restrictive mfa_* policy that now
-- calls the same combined guard; do not duplicate that per-row evaluation.
CREATE POLICY session_live_companies ON public.companies AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_courses ON public.courses AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_lesson_progress ON public.lesson_progress AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_lessons ON public.lessons AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_modules ON public.modules AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_redemptions ON public.redemptions AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
CREATE POLICY session_live_rewards ON public.rewards AS RESTRICTIVE TO authenticated USING (public.mfa_access_allowed()) WITH CHECK (public.mfa_access_allowed());
