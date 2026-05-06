-- STEP 1.3 — RLS policies for verification_requests and doctors update guard

-- ─── verification_requests RLS ───────────────────────────────────────────────

ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

-- Doctors can submit their own request
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='verification_requests' AND policyname='doctor inserts own request'
  ) THEN
    CREATE POLICY "doctor inserts own request"
      ON public.verification_requests FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = doctor_id);
  END IF;
END $$;

-- Doctors can view their own request
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='verification_requests' AND policyname='doctor views own request'
  ) THEN
    CREATE POLICY "doctor views own request"
      ON public.verification_requests FOR SELECT
      TO authenticated
      USING (auth.uid() = doctor_id);
  END IF;
END $$;

-- Admins (anon with password gate) can view all requests
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='verification_requests' AND policyname='anon admin views all requests'
  ) THEN
    CREATE POLICY "anon admin views all requests"
      ON public.verification_requests FOR SELECT
      TO anon USING (true);
  END IF;
END $$;

-- Admins can update status / admin_notes
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='verification_requests' AND policyname='anon admin updates requests'
  ) THEN
    CREATE POLICY "anon admin updates requests"
      ON public.verification_requests FOR UPDATE
      TO anon
      USING (true)
      WITH CHECK (status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

-- Grants
GRANT SELECT, INSERT ON public.verification_requests TO authenticated;
GRANT SELECT, UPDATE (status, admin_notes, updated_at) ON public.verification_requests TO anon;

-- ─── Trigger: approval sets doctors.is_verified = true ───────────────────────

CREATE OR REPLACE FUNCTION public.sync_doctor_verified_on_request_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    UPDATE public.doctors
      SET is_verified = TRUE
      WHERE owner_user_id = NEW.doctor_id;
  ELSIF NEW.status = 'rejected' AND OLD.status = 'approved' THEN
    UPDATE public.doctors
      SET is_verified = FALSE
      WHERE owner_user_id = NEW.doctor_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_doctor_verified ON public.verification_requests;
CREATE TRIGGER trg_sync_doctor_verified
  AFTER UPDATE OF status ON public.verification_requests
  FOR EACH ROW EXECUTE FUNCTION public.sync_doctor_verified_on_request_update();

-- ─── doctors: RLS for authenticated update (owner & verified) ────────────────
-- Doctors can only update their own record if is_verified = true.
-- Uses DO block to avoid error on duplicate policy name.

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='doctors' AND policyname='verified owner updates own doctor row'
  ) THEN
    CREATE POLICY "verified owner updates own doctor row"
      ON public.doctors FOR UPDATE
      TO authenticated
      USING (auth.uid() = owner_user_id AND is_verified = TRUE)
      WITH CHECK (auth.uid() = owner_user_id AND is_verified = TRUE);
  END IF;
END $$;

-- Existing anon public-read and anon admin-update policies are preserved.
-- (They exist from earlier migrations and are not dropped here.)
