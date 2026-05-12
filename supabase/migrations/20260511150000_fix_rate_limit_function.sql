-- Fix within_rate_limit: remove column_name parameter,
-- always use 'user_id' column (consistent with all tables using it).
-- Also use %I quoting for the column to prevent SQL injection.

CREATE OR REPLACE FUNCTION public.within_rate_limit(
  p_table_name  text,
  p_max_count   int,
  p_window_secs int DEFAULT 3600
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
     WHERE user_id = auth.uid()
       AND created_at > now() - ($1 * interval ''1 second'')',
    p_table_name
  )
  INTO recent_count
  USING p_window_secs;
  RETURN recent_count < p_max_count;
END;
$$;

REVOKE ALL ON FUNCTION public.within_rate_limit(text, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.within_rate_limit(text, int, int) TO authenticated;

-- Update all policies to use the new 3-parameter signature:

-- reports
DROP POLICY IF EXISTS "reports_insert_authenticated_rate_limited" ON public.reports;
CREATE POLICY "reports_insert_authenticated_rate_limited"
ON public.reports FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND public.within_rate_limit('reports', 10, 3600)
);

-- pending_doctors
DROP POLICY IF EXISTS "pending_doctors_insert_rate_limited" ON public.pending_doctors;
CREATE POLICY "pending_doctors_insert_rate_limited"
ON public.pending_doctors FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND public.within_rate_limit('pending_doctors', 3, 86400)
);

-- verification_requests
DROP POLICY IF EXISTS "verification_requests_insert_rate_limited" ON public.verification_requests;
CREATE POLICY "verification_requests_insert_rate_limited"
ON public.verification_requests FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() IS NOT NULL
  AND public.within_rate_limit('verification_requests', 2, 604800)
);
