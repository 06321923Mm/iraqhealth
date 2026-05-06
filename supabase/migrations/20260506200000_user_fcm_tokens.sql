-- FCM push token storage — one row per authenticated user, upserted on login.

CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
  user_id     UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token   TEXT        NOT NULL,
  platform    TEXT        NOT NULL DEFAULT 'android'
    CONSTRAINT user_fcm_tokens_platform_check
    CHECK (platform IN ('android', 'ios', 'web')),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Each user can only upsert and read their own token.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'user_fcm_tokens' AND policyname = 'owner upserts own fcm token'
  ) THEN
    CREATE POLICY "owner upserts own fcm token"
      ON public.user_fcm_tokens FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'user_fcm_tokens' AND policyname = 'owner updates own fcm token'
  ) THEN
    CREATE POLICY "owner updates own fcm token"
      ON public.user_fcm_tokens FOR UPDATE
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Service role (Edge Functions) can read any token.
GRANT SELECT, INSERT, UPDATE ON public.user_fcm_tokens TO authenticated;

COMMENT ON TABLE public.user_fcm_tokens IS 'Stores Firebase Cloud Messaging device tokens per user for push notifications.';
