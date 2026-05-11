-- Ensure INSERT works for both anon and authenticated users
-- Fixes "permission denied" (code 42501) from AddClinicPage

GRANT INSERT ON public.pending_doctors TO anon, authenticated;

ALTER TABLE public.pending_doctors ENABLE ROW LEVEL SECURITY;

-- Drop any conflicting old policies
DROP POLICY IF EXISTS "Anyone can insert pending_doctors"    ON public.pending_doctors;
DROP POLICY IF EXISTS "anyone_insert_pending"                ON public.pending_doctors;
DROP POLICY IF EXISTS "anon_insert_pending_doctors"          ON public.pending_doctors;
DROP POLICY IF EXISTS "pending_doctors_insert_rate_limited"  ON public.pending_doctors;

-- Single clean policy: anyone can submit a new clinic
CREATE POLICY "anyone_can_submit_new_clinic"
  ON public.pending_doctors
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);
