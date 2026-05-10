-- محفّز check_admin_role كان يعيد RETURN NEW بعد DELETE؛ في محفّزات DELETE تكون NEW = NULL فيُلغى الحذف دون رسالة — الطلب يبقى في القائمة.
-- كذلك مسار service_role يجب أن يعيد OLD عند DELETE.
-- توحيد تحقق الأدمن: app_metadata أو user_metadata (لمن ضبط الدور في المكان الخطأ من لوحة Supabase).

CREATE OR REPLACE FUNCTION public.jwt_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    nullif(trim(auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin'
    OR nullif(trim(auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin',
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.check_admin_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND TG_TABLE_NAME = 'doctors' THEN
    IF NOT public.jwt_is_admin() THEN
      RAISE EXCEPTION 'إضافة عيادة تتطلب صلاحية الإدارة.';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الإدارة.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- دوال الأدمن SECURITY DEFINER — نفس تعريف الأدمن عبر JWT
CREATE OR REPLACE FUNCTION public.admin_approve_verification(
  p_request_id uuid,
  p_doctor_id integer
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.jwt_is_admin() THEN
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

CREATE OR REPLACE FUNCTION public.admin_reject_verification(
  p_request_id uuid,
  p_admin_notes text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.jwt_is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.verification_requests
    SET status = 'rejected', admin_notes = p_admin_notes, updated_at = now()
    WHERE id = p_request_id;
END;
$$;

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
  IF NOT public.jwt_is_admin() THEN
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
  IF NOT public.jwt_is_admin() THEN
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

-- سياسات RLS: قبول أدمن من user_metadata أيضاً
DROP POLICY IF EXISTS "admin_update_reports" ON public.reports;
CREATE POLICY "admin_update_reports" ON public.reports
  FOR UPDATE TO authenticated
  USING (public.jwt_is_admin())
  WITH CHECK (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin_delete_reports" ON public.reports;
CREATE POLICY "admin_delete_reports" ON public.reports
  FOR DELETE TO authenticated
  USING (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin_select_reports" ON public.reports;
CREATE POLICY "admin_select_reports" ON public.reports
  FOR SELECT TO authenticated
  USING (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin_delete_pending" ON public.pending_doctors;
CREATE POLICY "admin_delete_pending" ON public.pending_doctors
  FOR DELETE TO authenticated
  USING (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin_select_pending" ON public.pending_doctors;
CREATE POLICY "admin_select_pending" ON public.pending_doctors
  FOR SELECT TO authenticated
  USING (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin all claims" ON public.clinic_claim_requests;
CREATE POLICY "admin all claims" ON public.clinic_claim_requests
  FOR ALL TO authenticated
  USING (public.jwt_is_admin())
  WITH CHECK (public.jwt_is_admin());

DROP POLICY IF EXISTS "admin all verification" ON public.verification_requests;
CREATE POLICY "admin all verification" ON public.verification_requests
  FOR ALL TO authenticated
  USING (public.jwt_is_admin())
  WITH CHECK (public.jwt_is_admin());

GRANT EXECUTE ON FUNCTION public.jwt_is_admin() TO authenticated;
