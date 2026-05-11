-- Allow anon key to UPDATE all needed doctor fields
-- Fixes _applyDirectCorrection "permission denied" on doctors table

GRANT UPDATE (
  name, spec, addr, ph, ph2, notes, area, gove, latitude, longitude
) ON public.doctors TO anon;

-- Ensure RLS policy exists for anon UPDATE
DROP POLICY IF EXISTS "Anon admin can update doctor fields" ON public.doctors;

CREATE POLICY "anon_admin_update_doctors"
  ON public.doctors
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);

-- Also ensure reports can be updated by anon (mark as resolved)
GRANT UPDATE (status) ON public.reports TO anon;

DROP POLICY IF EXISTS "Anon admin can update report status" ON public.reports;

CREATE POLICY "anon_can_resolve_reports"
  ON public.reports
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed'));
