-- ✅ UPDATED 2026-05-09
-- Final security + flow fixes (idempotent)

-- 1) check_admin_role trigger fix
CREATE OR REPLACE FUNCTION check_admin_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- service_role bypasses checks
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- INSERT on doctors only for admin
  IF TG_OP = 'INSERT' AND TG_TABLE_NAME = 'doctors' THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
      RAISE EXCEPTION 'إضافة عيادة تتطلب صلاحية الإدارة.';
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT on pending_doctors / reports allowed
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  -- UPDATE / DELETE requires admin
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الإدارة.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_admin_update_doctors ON public.doctors;
CREATE TRIGGER enforce_admin_update_doctors
  BEFORE INSERT OR UPDATE OR DELETE ON public.doctors
  FOR EACH ROW EXECUTE FUNCTION check_admin_role();

DROP TRIGGER IF EXISTS enforce_admin_update_reports ON public.reports;
CREATE TRIGGER enforce_admin_update_reports
  BEFORE UPDATE OR DELETE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION check_admin_role();

DROP TRIGGER IF EXISTS enforce_admin_pending_doctors ON public.pending_doctors;
CREATE TRIGGER enforce_admin_pending_doctors
  BEFORE UPDATE OR DELETE ON public.pending_doctors
  FOR EACH ROW EXECUTE FUNCTION check_admin_role();

DROP TRIGGER IF EXISTS enforce_admin_clinic_claims ON public.clinic_claim_requests;
CREATE TRIGGER enforce_admin_clinic_claims
  BEFORE UPDATE OR DELETE ON public.clinic_claim_requests
  FOR EACH ROW EXECUTE FUNCTION check_admin_role();

-- 2) verification_requests RLS
ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "doctor views own verification" ON public.verification_requests;
CREATE POLICY "doctor views own verification"
ON public.verification_requests
  FOR SELECT TO authenticated
  USING (doctor_id::text IN (SELECT id::text FROM public.doctors WHERE owner_user_id = auth.uid()));

DROP POLICY IF EXISTS "doctor inserts own verification" ON public.verification_requests;
CREATE POLICY "doctor inserts own verification"
ON public.verification_requests
  FOR INSERT TO authenticated
  WITH CHECK (doctor_id::text IN (SELECT id::text FROM public.doctors WHERE owner_user_id = auth.uid()));

DROP POLICY IF EXISTS "admin all verification" ON public.verification_requests;
CREATE POLICY "admin all verification"
ON public.verification_requests
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 3) clinic_claim_requests RLS
ALTER TABLE public.clinic_claim_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user views own claims" ON public.clinic_claim_requests;
CREATE POLICY "user views own claims"
ON public.clinic_claim_requests
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user inserts own claim" ON public.clinic_claim_requests;
CREATE POLICY "user inserts own claim"
ON public.clinic_claim_requests
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "admin all claims" ON public.clinic_claim_requests;
CREATE POLICY "admin all claims"
ON public.clinic_claim_requests
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- 4) RPC: admin approve verification
CREATE OR REPLACE FUNCTION public.admin_approve_verification(
  p_request_id uuid,
  p_doctor_id integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.verification_requests
    SET status = 'approved', updated_at = now()
    WHERE id = p_request_id;

  UPDATE public.doctors
    SET is_verified = true
    WHERE id = p_doctor_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_verification(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_approve_verification(uuid, integer) TO authenticated;

-- 5) RPC: admin reject verification
CREATE OR REPLACE FUNCTION public.admin_reject_verification(
  p_request_id uuid,
  p_admin_notes text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.verification_requests
    SET status = 'rejected', admin_notes = p_admin_notes, updated_at = now()
    WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_verification(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_reject_verification(uuid, text) TO authenticated;

-- 6) RPC: apply report correction on doctors
CREATE OR REPLACE FUNCTION public.admin_apply_report_correction(
  p_report_id uuid,
  p_doctor_id integer,
  p_field_name text,
  p_new_value text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  allowed_fields text[] := ARRAY['name','spec','addr','ph','ph2','notes','area','gove'];
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF NOT (p_field_name = ANY(allowed_fields)) THEN
    RAISE EXCEPTION 'حقل غير مسموح بتعديله: %', p_field_name;
  END IF;

  EXECUTE format('UPDATE public.doctors SET %I = $1 WHERE id = $2', p_field_name)
    USING p_new_value, p_doctor_id;

  UPDATE public.reports SET status = 'resolved' WHERE id = p_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_apply_report_correction(uuid, integer, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_apply_report_correction(uuid, integer, text, text) TO authenticated;

-- 7) RPC: apply coordinate correction from reports
CREATE OR REPLACE FUNCTION public.admin_apply_coord_correction(
  p_report_id uuid,
  p_doctor_id integer,
  p_lat double precision,
  p_lng double precision
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.doctors
    SET latitude = p_lat, longitude = p_lng
    WHERE id = p_doctor_id;

  UPDATE public.reports
    SET status = 'resolved'
    WHERE id = p_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_apply_coord_correction(uuid, integer, double precision, double precision) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_apply_coord_correction(uuid, integer, double precision, double precision) TO authenticated;
