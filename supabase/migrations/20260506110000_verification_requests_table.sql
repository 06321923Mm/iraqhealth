-- STEP 1.2 — Create verification_requests table

CREATE TABLE IF NOT EXISTS public.verification_requests (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id_card_front_url  TEXT,
  id_card_back_url   TEXT,
  medical_license_url TEXT,
  status             TEXT        NOT NULL DEFAULT 'pending'
    CONSTRAINT verification_requests_status_check
    CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_notes        TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Only one active (pending/approved) request per doctor at a time
CREATE UNIQUE INDEX IF NOT EXISTS verification_requests_doctor_active_idx
  ON public.verification_requests (doctor_id)
  WHERE status = 'pending';

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_verification_requests_updated_at ON public.verification_requests;
CREATE TRIGGER trg_verification_requests_updated_at
  BEFORE UPDATE ON public.verification_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.verification_requests IS 'Doctor identity & license verification requests reviewed by admin.';
