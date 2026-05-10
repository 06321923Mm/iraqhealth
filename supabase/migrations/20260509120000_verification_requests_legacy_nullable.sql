-- After bigint migration, new rows only set doctor_id; doctor_user_id_legacy is deprecated
-- and must not block inserts.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'verification_requests'
      AND column_name = 'doctor_user_id_legacy'
  ) THEN
    EXECUTE
      'ALTER TABLE public.verification_requests ALTER COLUMN doctor_user_id_legacy DROP NOT NULL';
  END IF;
END $$;
