-- Track admin RPCs in version control with jwt_is_admin() guards.
-- Signatures match public.admin_* from 20260509000000_final_security_and_flow_fixes.sql
-- and 20260510130000_doctors_trust_layer.sql (p_doctor_id is integer / doctors.id).

-- 1) admin_approve_verification
CREATE OR REPLACE FUNCTION public.admin_approve_verification(
  p_request_id uuid,
  p_doctor_id  integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  UPDATE public.verification_requests SET status = 'approved', updated_at = now() WHERE id = p_request_id;
  UPDATE public.doctors
    SET is_verified = true, verification_date = COALESCE(verification_date, now())
    WHERE id = p_doctor_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_verification(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_approve_verification(uuid, integer) TO authenticated;

-- 2) admin_reject_verification
CREATE OR REPLACE FUNCTION public.admin_reject_verification(
  p_request_id   uuid,
  p_admin_notes  text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  UPDATE public.verification_requests SET status = 'rejected', admin_notes = p_admin_notes, updated_at = now() WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_verification(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_reject_verification(uuid, text) TO authenticated;

-- 3) admin_apply_coord_correction
CREATE OR REPLACE FUNCTION public.admin_apply_coord_correction(
  p_report_id uuid,
  p_doctor_id integer,
  p_lat       double precision,
  p_lng       double precision
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  UPDATE public.doctors SET latitude = p_lat, longitude = p_lng WHERE id = p_doctor_id;
  UPDATE public.reports SET status = 'resolved' WHERE id = p_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_apply_coord_correction(uuid, integer, double precision, double precision) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_apply_coord_correction(uuid, integer, double precision, double precision) TO authenticated;

-- 4) admin_apply_report_correction
CREATE OR REPLACE FUNCTION public.admin_apply_report_correction(
  p_report_id   uuid,
  p_doctor_id   integer,
  p_field_name  text,
  p_new_value   text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  allowed_fields text[] := ARRAY['name','spec','addr','ph','ph2','notes','area','gove'];
BEGIN
  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF NOT (p_field_name = ANY(allowed_fields)) THEN
    RAISE EXCEPTION 'حقل غير مسموح بتعديله: %', p_field_name;
  END IF;
  EXECUTE format('UPDATE public.doctors SET %I = $1 WHERE id = $2', p_field_name) USING p_new_value, p_doctor_id;
  UPDATE public.reports SET status = 'resolved' WHERE id = p_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_apply_report_correction(uuid, integer, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_apply_report_correction(uuid, integer, text, text) TO authenticated;
