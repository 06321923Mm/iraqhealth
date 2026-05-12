-- 1. Enable RLS and secure doctor_report_totals
ALTER TABLE IF EXISTS public.doctor_report_totals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "doctor_report_totals_select" ON public.doctor_report_totals;
CREATE POLICY "doctor_report_totals_select"
ON public.doctor_report_totals FOR SELECT
USING (true); -- Public read access for totals

DROP POLICY IF EXISTS "doctor_report_totals_all_admin" ON public.doctor_report_totals;
CREATE POLICY "doctor_report_totals_all_admin"
ON public.doctor_report_totals FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 2. Clean up old overly permissive policies from reports and doctors (if they still exist)
DROP POLICY IF EXISTS "anyone insert reports" ON public.reports;
DROP POLICY IF EXISTS "anon_insert_reports" ON public.reports;
DROP POLICY IF EXISTS "anon_update_doctors" ON public.doctors;
DROP POLICY IF EXISTS "anon_delete_doctors" ON public.doctors;
