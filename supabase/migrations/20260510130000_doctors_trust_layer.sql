-- TASK 5: Trust layer columns + automatic maintenance.

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS verification_date    timestamptz,
  ADD COLUMN IF NOT EXISTS last_status_update   timestamptz,
  ADD COLUMN IF NOT EXISTS report_ratio         real        NOT NULL DEFAULT 0.0;

-- Backfill verification_date for already-verified doctors.
UPDATE public.doctors
   SET verification_date = COALESCE(verification_date, now())
 WHERE is_verified = true
   AND verification_date IS NULL;

-- Trigger: when current_status / status_message / status_expires_at change, stamp last_status_update.
CREATE OR REPLACE FUNCTION public.touch_doctor_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.current_status     IS DISTINCT FROM OLD.current_status
     OR NEW.status_message    IS DISTINCT FROM OLD.status_message
     OR NEW.status_expires_at IS DISTINCT FROM OLD.status_expires_at THEN
    NEW.last_status_update := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_doctor_status_touch ON public.doctors;
CREATE TRIGGER trg_doctor_status_touch
  BEFORE UPDATE ON public.doctors
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_doctor_status_update();

-- Trigger: stamp verification_date the moment is_verified flips to true.
CREATE OR REPLACE FUNCTION public.stamp_verification_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_verified = true AND COALESCE(OLD.is_verified, false) = false THEN
    NEW.verification_date := COALESCE(NEW.verification_date, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_doctor_verification_stamp ON public.doctors;
CREATE TRIGGER trg_doctor_verification_stamp
  BEFORE UPDATE OF is_verified ON public.doctors
  FOR EACH ROW
  EXECUTE FUNCTION public.stamp_verification_date();

-- Function: refresh report_ratio from doctor_report_totals (or reports table count).
-- We avoid an expensive trigger on reports inserts by exposing a callable RPC the
-- admin tools can invoke periodically (or you can wire a pg_cron job).
CREATE OR REPLACE FUNCTION public.refresh_doctor_report_ratios()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_reports bigint;
BEGIN
  SELECT COUNT(*) INTO v_total_reports FROM public.reports;
  IF v_total_reports = 0 THEN
    UPDATE public.doctors SET report_ratio = 0.0 WHERE report_ratio <> 0.0;
    RETURN;
  END IF;
  UPDATE public.doctors d
     SET report_ratio = COALESCE(t.ratio, 0.0)
    FROM (
      SELECT r.doctor_id::int AS doctor_id,
             (COUNT(*)::real / v_total_reports::real) AS ratio
        FROM public.reports r
       WHERE r.doctor_id IS NOT NULL
       GROUP BY r.doctor_id
    ) t
   WHERE d.id = t.doctor_id
     AND d.report_ratio IS DISTINCT FROM COALESCE(t.ratio, 0.0);
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_doctor_report_ratios() FROM public;
GRANT EXECUTE ON FUNCTION public.refresh_doctor_report_ratios() TO authenticated;

-- Update RPC: admin_approve_verification stamps verification_date too.
CREATE OR REPLACE FUNCTION public.admin_approve_verification(
  p_request_id uuid,
  p_doctor_id  integer
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
     SET status     = 'approved',
         updated_at = now()
   WHERE id = p_request_id;

  UPDATE public.doctors
     SET is_verified       = true,
         verification_date = COALESCE(verification_date, now())
   WHERE id = p_doctor_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_verification(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_approve_verification(uuid, integer)
  TO authenticated;
