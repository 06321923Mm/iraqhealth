-- TASK 7: Daily report rate-limit (anti-spam).
-- Caps each authenticated user to N reports per UTC day.

CREATE TABLE IF NOT EXISTS public.daily_report_counts (
  user_id      uuid    NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  report_date  date    NOT NULL,
  count        integer NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, report_date)
);

CREATE INDEX IF NOT EXISTS daily_report_counts_user_date_idx
  ON public.daily_report_counts (user_id, report_date);

ALTER TABLE public.daily_report_counts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user reads own report counters" ON public.daily_report_counts;
CREATE POLICY "user reads own report counters"
  ON public.daily_report_counts FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT ON public.daily_report_counts TO authenticated;

-- RPC: returns whether user can submit and the current count.
CREATE OR REPLACE FUNCTION public.daily_report_quota(p_max integer DEFAULT 5)
RETURNS TABLE (used integer, max_per_day integer, can_submit boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_used  integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN QUERY SELECT 0, p_max, false;
    RETURN;
  END IF;
  SELECT COALESCE(c.count, 0)
    INTO v_used
    FROM public.daily_report_counts c
   WHERE c.user_id = v_uid
     AND c.report_date = (now() AT TIME ZONE 'UTC')::date;
  RETURN QUERY SELECT COALESCE(v_used, 0), p_max, COALESCE(v_used, 0) < p_max;
END;
$$;

REVOKE ALL ON FUNCTION public.daily_report_quota(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.daily_report_quota(integer) TO authenticated;

-- Trigger on reports: increment counter and reject when over limit.
CREATE OR REPLACE FUNCTION public.enforce_daily_report_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_today     date := (now() AT TIME ZONE 'UTC')::date;
  v_max       integer := 5;
  v_existing  integer := 0;
  v_role      text;
BEGIN
  -- service_role and admin bypass the limit.
  v_role := current_setting('role', true);
  IF v_role = 'service_role'
     OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin' THEN
    RETURN NEW;
  END IF;

  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(count, 0)
    INTO v_existing
    FROM public.daily_report_counts
   WHERE user_id = v_uid AND report_date = v_today;

  IF v_existing >= v_max THEN
    RAISE EXCEPTION
      'تجاوزت الحد اليومي (% تقارير) لإرسال التقارير. حاول مجدداً غداً.',
      v_max
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.daily_report_counts (user_id, report_date, count, updated_at)
  VALUES (v_uid, v_today, 1, now())
  ON CONFLICT (user_id, report_date) DO UPDATE
    SET count      = public.daily_report_counts.count + 1,
        updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_daily_report_quota ON public.reports;
CREATE TRIGGER trg_enforce_daily_report_quota
  BEFORE INSERT ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_daily_report_quota();
