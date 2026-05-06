-- STEP 1.5 — pg_cron job: auto-expire doctor status
-- If pg_cron is not enabled this migration will fail gracefully.

DO $$
BEGIN
  -- Check if pg_cron extension exists
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- Remove existing job if any
    PERFORM cron.unschedule('expire-doctor-status')
    WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'expire-doctor-status'
    );

    -- Schedule every 5 minutes
    PERFORM cron.schedule(
      'expire-doctor-status',
      '*/5 * * * *',
      $cronbody$
        UPDATE public.doctors
        SET
          current_status = 'closed',
          status_message = NULL
        WHERE
          status_expires_at < NOW()
          AND status_expires_at IS NOT NULL
          AND current_status != 'closed'
      $cronbody$
    );

    RAISE NOTICE 'pg_cron job "expire-doctor-status" scheduled successfully.';
  ELSE
    RAISE NOTICE 'pg_cron extension not found — skipping cron job. Enable it in Supabase Dashboard > Database > Extensions.';
  END IF;
END;
$$;
