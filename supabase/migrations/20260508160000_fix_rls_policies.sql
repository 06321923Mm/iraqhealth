-- إعادة بناء check_admin_role مع السماح بـ INSERT للكل
CREATE OR REPLACE FUNCTION check_admin_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN RETURN NEW; END IF;
  IF current_setting('role', true) = 'service_role' THEN RETURN NEW; END IF;
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الإدارة.';
  END IF;
  RETURN NEW;
END;
$$;

-- مسح السياسات القديمة
DROP POLICY IF EXISTS "Anyone can insert reports" ON public.reports;
DROP POLICY IF EXISTS "Anon admin can update report status" ON public.reports;
DROP POLICY IF EXISTS "admin manage reports" ON public.reports;
DROP POLICY IF EXISTS "admin can update reports" ON public.reports;
DROP POLICY IF EXISTS "admin can delete reports" ON public.reports;
DROP POLICY IF EXISTS "admin can view reports" ON public.reports;
DROP POLICY IF EXISTS "Anyone can insert pending_doctors" ON public.pending_doctors;
DROP POLICY IF EXISTS "Anon admin can delete pending_doctors" ON public.pending_doctors;
DROP POLICY IF EXISTS "admin manage pending_doctors" ON public.pending_doctors;
DROP POLICY IF EXISTS "admin can view pending_doctors" ON public.pending_doctors;
DROP POLICY IF EXISTS "anon admin sees all" ON public.clinic_claim_requests;
DROP POLICY IF EXISTS "anon admin updates status" ON public.clinic_claim_requests;
DROP POLICY IF EXISTS "admin can view claims" ON public.clinic_claim_requests;
DROP POLICY IF EXISTS "auth user sees own requests" ON public.clinic_claim_requests;
DROP POLICY IF EXISTS "auth user inserts own request" ON public.clinic_claim_requests;
DROP POLICY IF EXISTS "doctor inserts own request" ON public.verification_requests;
DROP POLICY IF EXISTS "doctor views own request" ON public.verification_requests;
DROP POLICY IF EXISTS "anon admin views all requests" ON public.verification_requests;
DROP POLICY IF EXISTS "anon admin updates requests" ON public.verification_requests;
DROP POLICY IF EXISTS "admin can view verification_requests" ON public.verification_requests;
DROP POLICY IF EXISTS "admin can update verification" ON public.verification_requests;
DROP POLICY IF EXISTS "Anon admin can update doctor fields" ON public.doctors;
DROP POLICY IF EXISTS "Anon admin can insert doctors" ON public.doctors;
DROP POLICY IF EXISTS "verified owner updates own doctor row" ON public.doctors;
DROP POLICY IF EXISTS "admin can manage doctors" ON public.doctors;
DROP POLICY IF EXISTS "anyone_read_doctors" ON public.doctors;
DROP POLICY IF EXISTS "admin_all_doctors" ON public.doctors;

-- سياسات reports
CREATE POLICY "anyone_insert_reports" ON public.reports FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "admin_update_reports" ON public.reports FOR UPDATE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin') WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_delete_reports" ON public.reports FOR DELETE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_select_reports" ON public.reports FOR SELECT TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- سياسات pending_doctors
CREATE POLICY "anyone_insert_pending" ON public.pending_doctors FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY "admin_delete_pending" ON public.pending_doctors FOR DELETE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_select_pending" ON public.pending_doctors FOR SELECT TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- سياسات clinic_claim_requests
CREATE POLICY "user_insert_own_claim" ON public.clinic_claim_requests FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "admin_update_claims" ON public.clinic_claim_requests FOR UPDATE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_select_claims" ON public.clinic_claim_requests FOR SELECT TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- سياسات verification_requests
CREATE POLICY "owner_insert_verif" ON public.verification_requests FOR INSERT TO authenticated WITH CHECK (doctor_id = auth.uid());
CREATE POLICY "admin_update_verif" ON public.verification_requests FOR UPDATE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_select_verif" ON public.verification_requests FOR SELECT TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- سياسات doctors (مقسّمة بدون تعارض)
CREATE POLICY "anyone_read_doctors" ON public.doctors FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "admin_insert_doctors" ON public.doctors FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_update_doctors" ON public.doctors FOR UPDATE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin') WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_delete_doctors" ON public.doctors FOR DELETE TO authenticated USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- صلاحيات الجداول
GRANT INSERT ON public.reports TO anon, authenticated;
GRANT INSERT ON public.pending_doctors TO anon, authenticated;
GRANT INSERT, SELECT ON public.clinic_claim_requests TO authenticated;
GRANT INSERT, SELECT ON public.verification_requests TO authenticated;
GRANT SELECT ON public.doctors TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.doctors TO authenticated;

-- التحقق من بقاء الـ Triggers
SELECT tgname, relname FROM pg_trigger
JOIN pg_class ON pg_class.oid = pg_trigger.tgrelid
WHERE tgname LIKE 'enforce_admin%';
