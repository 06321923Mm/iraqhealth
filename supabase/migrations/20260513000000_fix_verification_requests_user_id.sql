-- Add user_id column to verification_requests with default auth.uid()
ALTER TABLE public.verification_requests
  ADD COLUMN IF NOT EXISTS user_id uuid DEFAULT auth.uid();

-- Backfill user_id from doctor_user_id_legacy where user_id is null
UPDATE public.verification_requests
SET user_id = doctor_user_id_legacy
WHERE user_id IS NULL
  AND doctor_user_id_legacy IS NOT NULL;

-- Drop the old 4-parameter overload of within_rate_limit
DROP FUNCTION IF EXISTS public.within_rate_limit(text, text, int, int);
