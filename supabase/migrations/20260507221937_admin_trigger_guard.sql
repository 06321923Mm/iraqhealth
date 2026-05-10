CREATE OR REPLACE FUNCTION check_admin_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

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