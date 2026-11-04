CREATE TABLE public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT true
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY notification_preferences_select ON public.notification_preferences
  FOR SELECT TO authenticated USING (user_id = auth.uid());

GRANT SELECT ON TABLE public.notification_preferences TO authenticated;
GRANT ALL ON TABLE public.notification_preferences TO service_role;
