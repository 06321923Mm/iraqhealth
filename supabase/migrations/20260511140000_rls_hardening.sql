-- ══════════════════════════════════════════════════════════════
-- MIGRATION: RLS Hardening + Rate Limiting
-- Applies to: iraq_health / iraqhealth-b08f6
-- Tables: reports, pending_doctors, verification_requests, doctors
-- ══════════════════════════════════════════════════════════════

-- Ensure rate-limit columns exist (defaults fill user_id on INSERT).
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS user_id uuid DEFAULT auth.uid();

ALTER TABLE public.pending_doctors
  ADD COLUMN IF NOT EXISTS user_id uuid DEFAULT auth.uid();

-- ── 1. Helper: check if current user is admin ─────────────────────────────
-- Delegates to jwt_is_admin() (app_metadata + user_metadata) from prior migrations.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.jwt_is_admin();
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon;

-- ── 2. Helper: rate-limit check ───────────────────────────────────────────
-- [id_column] must be a simple identifier on [table_name] (e.g. user_id, doctor_user_id_legacy).

CREATE OR REPLACE FUNCTION public.within_rate_limit(
  table_name   text,
  id_column    text,
  max_count    int,
  window_secs  int DEFAULT 3600
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recent_count int;
BEGIN
  EXECUTE format(
    'SELECT COUNT(*) FROM %I
     WHERE %I = auth.uid()
       AND created_at > now() - ($1 * interval ''1 second'')',
    table_name,
    id_column
  )
  INTO recent_count
  USING window_secs;
  RETURN recent_count < max_count;
END;
$$;

REVOKE ALL ON FUNCTION public.within_rate_limit(text, text, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.within_rate_limit(text, text, int, int) TO authenticated;

-- ── 3. TABLE: reports ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS "reports_insert_anon"    ON public.reports;
DROP POLICY IF EXISTS "reports_insert_auth"    ON public.reports;
DROP POLICY IF EXISTS "reports_insert"         ON public.reports;
DROP POLICY IF EXISTS "anyone_insert_reports"  ON public.reports;
DROP POLICY IF EXISTS "reports_insert_authenticated_rate_limited" ON public.reports;

CREATE POLICY "reports_insert_authenticated_rate_limited"
ON public.reports
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND user_id IS NOT DISTINCT FROM auth.uid()
  AND public.within_rate_limit('reports', 'user_id', 10, 3600)
);

DROP POLICY IF EXISTS "reports_select" ON public.reports;

CREATE POLICY "reports_select"
ON public.reports
FOR SELECT
USING (
  auth.uid() = user_id
  OR public.is_admin()
);

DROP POLICY IF EXISTS "reports_update" ON public.reports;
DROP POLICY IF EXISTS "reports_delete" ON public.reports;
DROP POLICY IF EXISTS "admin_update_reports" ON public.reports;
DROP POLICY IF EXISTS "admin_delete_reports" ON public.reports;
DROP POLICY IF EXISTS "reports_update_admin_only" ON public.reports;
DROP POLICY IF EXISTS "reports_delete_admin_only" ON public.reports;

CREATE POLICY "reports_update_admin_only"
ON public.reports
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY "reports_delete_admin_only"
ON public.reports
FOR DELETE
TO authenticated
USING (public.is_admin());

-- ── 4. TABLE: pending_doctors ─────────────────────────────────────────────

DROP POLICY IF EXISTS "pending_doctors_insert" ON public.pending_doctors;
DROP POLICY IF EXISTS "pending_doctors_insert_rate_limited" ON public.pending_doctors;
DROP POLICY IF EXISTS "Anyone can insert pending_doctors" ON public.pending_doctors;

CREATE POLICY "pending_doctors_insert_rate_limited"
ON public.pending_doctors
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND user_id IS NOT DISTINCT FROM auth.uid()
  AND public.within_rate_limit('pending_doctors', 'user_id', 3, 86400)
);

DROP POLICY IF EXISTS "pending_doctors_select" ON public.pending_doctors;

CREATE POLICY "pending_doctors_select"
ON public.pending_doctors
FOR SELECT
USING (
  auth.uid() = user_id
  OR public.is_admin()
);

DROP POLICY IF EXISTS "pending_doctors_update" ON public.pending_doctors;
DROP POLICY IF EXISTS "pending_doctors_delete" ON public.pending_doctors;
DROP POLICY IF EXISTS "admin_delete_pending" ON public.pending_doctors;
DROP POLICY IF EXISTS "admin_select_pending" ON public.pending_doctors;
DROP POLICY IF EXISTS "pending_doctors_update_admin_only" ON public.pending_doctors;
DROP POLICY IF EXISTS "pending_doctors_delete_admin_only" ON public.pending_doctors;

CREATE POLICY "pending_doctors_update_admin_only"
ON public.pending_doctors
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

CREATE POLICY "pending_doctors_delete_admin_only"
ON public.pending_doctors
FOR DELETE
TO authenticated
USING (public.is_admin());

-- ── 5. TABLE: verification_requests ──────────────────────────────────────

DROP POLICY IF EXISTS "verification_requests_insert" ON public.verification_requests;
DROP POLICY IF EXISTS "verification_requests_insert_rate_limited" ON public.verification_requests;
DROP POLICY IF EXISTS "doctor inserts own verification" ON public.verification_requests;
DROP POLICY IF EXISTS "owner_insert_verif" ON public.verification_requests;

CREATE POLICY "verification_requests_insert_rate_limited"
ON public.verification_requests
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND doctor_user_id_legacy IS NOT DISTINCT FROM auth.uid()
  AND public.within_rate_limit('verification_requests', 'doctor_user_id_legacy', 2, 604800)
);

DROP POLICY IF EXISTS "verification_requests_select" ON public.verification_requests;
DROP POLICY IF EXISTS "doctor views own verification" ON public.verification_requests;
DROP POLICY IF EXISTS "owner_select_own_verif" ON public.verification_requests;
DROP POLICY IF EXISTS "admin_select_verif" ON public.verification_requests;
DROP POLICY IF EXISTS "admin all verification" ON public.verification_requests;

CREATE POLICY "verification_requests_select"
ON public.verification_requests
FOR SELECT
USING (
  auth.uid() = doctor_user_id_legacy
  OR public.is_admin()
);

DROP POLICY IF EXISTS "verification_requests_update" ON public.verification_requests;
DROP POLICY IF EXISTS "admin_update_verif" ON public.verification_requests;

CREATE POLICY "verification_requests_update_admin_only"
ON public.verification_requests
FOR UPDATE
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- ── 6. TABLE: doctors — tighten UPDATE ───────────────────────────────────

DROP POLICY IF EXISTS "doctors_update"       ON public.doctors;
DROP POLICY IF EXISTS "doctors_update_owner" ON public.doctors;
DROP POLICY IF EXISTS "doctors_update_owner_or_admin" ON public.doctors;
DROP POLICY IF EXISTS "verified owner updates own doctor row" ON public.doctors;
DROP POLICY IF EXISTS "admin_update_doctors" ON public.doctors;

CREATE POLICY "doctors_update_owner_or_admin"
ON public.doctors
FOR UPDATE
TO authenticated
USING (
  auth.uid() = owner_user_id
  OR public.is_admin()
)
WITH CHECK (
  auth.uid() = owner_user_id
  OR public.is_admin()
);

-- ── 7. Protect RPC functions with admin check ─────────────────────────────
-- Template for admin RPCs (apply manually in SQL Editor if bodies are unknown):
--
--   IF NOT public.is_admin() THEN
--     RAISE EXCEPTION 'permission_denied: admin role required'
--       USING ERRCODE = '42501';
--   END IF;
