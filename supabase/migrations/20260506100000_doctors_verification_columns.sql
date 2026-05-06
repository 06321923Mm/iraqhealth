-- STEP 1.1 — Add verification & status columns to doctors (additive only)

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS current_status TEXT NOT NULL DEFAULT 'closed'
    CONSTRAINT doctors_current_status_check
    CHECK (current_status IN ('online', 'busy', 'closed')),
  ADD COLUMN IF NOT EXISTS status_message TEXT,
  ADD COLUMN IF NOT EXISTS status_expires_at TIMESTAMPTZ;

COMMENT ON COLUMN public.doctors.is_verified         IS 'Set to TRUE by admin after identity/license verification.';
COMMENT ON COLUMN public.doctors.current_status      IS 'Doctor availability: online | busy | closed.';
COMMENT ON COLUMN public.doctors.status_message      IS 'Optional short message shown to patients.';
COMMENT ON COLUMN public.doctors.status_expires_at   IS 'Auto-reset to closed when this timestamp passes.';
