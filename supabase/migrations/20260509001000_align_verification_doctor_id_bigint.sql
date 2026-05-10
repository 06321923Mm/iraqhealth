-- Align verification_requests.doctor_id with public.doctors.id (bigint/int8).
-- Idempotent and safe to run multiple times.

DO $$
DECLARE
  v_col_type text;
  v_unmatched_count bigint;
  v_constraint_name text;
BEGIN
  SELECT c.data_type
  INTO v_col_type
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'verification_requests'
    AND c.column_name = 'doctor_id';

  IF v_col_type IS NULL THEN
    RAISE NOTICE 'Column public.verification_requests.doctor_id not found, skipping.';
    RETURN;
  END IF;

  -- If already bigint, no structural conversion needed.
  IF v_col_type = 'bigint' THEN
    RAISE NOTICE 'doctor_id is already bigint, skipping type conversion.';
  ELSE
    -- Drop RLS policies that depend on doctor_id expression before conversion.
    EXECUTE 'DROP POLICY IF EXISTS "doctor views own verification" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "doctor inserts own verification" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "admin all verification" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "owner_select_own_verif" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "owner_insert_verif" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "admin_select_verif" ON public.verification_requests';
    EXECUTE 'DROP POLICY IF EXISTS "admin_update_verif" ON public.verification_requests';

    -- Drop any FK constraints that include doctor_id.
    FOR v_constraint_name IN
      SELECT tc.constraint_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON kcu.constraint_name = tc.constraint_name
       AND kcu.constraint_schema = tc.constraint_schema
      WHERE tc.table_schema = 'public'
        AND tc.table_name = 'verification_requests'
        AND tc.constraint_type = 'FOREIGN KEY'
        AND kcu.column_name = 'doctor_id'
    LOOP
      EXECUTE format(
        'ALTER TABLE public.verification_requests DROP CONSTRAINT IF EXISTS %I',
        v_constraint_name
      );
    END LOOP;

    -- Add temporary bigint column when absent.
    ALTER TABLE public.verification_requests
      ADD COLUMN IF NOT EXISTS doctor_id_int bigint;

    -- Map legacy uuid doctor_id -> doctors.id by owner_user_id.
    UPDATE public.verification_requests vr
    SET doctor_id_int = d.id
    FROM public.doctors d
    WHERE vr.doctor_id_int IS NULL
      AND d.owner_user_id IS NOT NULL
      AND d.owner_user_id::text = vr.doctor_id::text;

    SELECT count(*)
    INTO v_unmatched_count
    FROM public.verification_requests
    WHERE doctor_id_int IS NULL;

    IF v_unmatched_count > 0 THEN
      RAISE EXCEPTION
        'Cannot convert verification_requests.doctor_id to bigint: % row(s) have no matching doctors.owner_user_id.',
        v_unmatched_count;
    END IF;

    ALTER TABLE public.verification_requests
      ALTER COLUMN doctor_id_int SET NOT NULL;

    -- Preserve legacy source then swap columns.
    ALTER TABLE public.verification_requests
      RENAME COLUMN doctor_id TO doctor_user_id_legacy;

    ALTER TABLE public.verification_requests
      RENAME COLUMN doctor_id_int TO doctor_id;
  END IF;

  -- Ensure FK + index on bigint doctor_id.
  ALTER TABLE public.verification_requests
    DROP CONSTRAINT IF EXISTS verification_requests_doctor_id_fkey;

  ALTER TABLE public.verification_requests
    ADD CONSTRAINT verification_requests_doctor_id_fkey
    FOREIGN KEY (doctor_id) REFERENCES public.doctors(id) ON DELETE CASCADE;

  CREATE INDEX IF NOT EXISTS verification_requests_doctor_id_idx
    ON public.verification_requests (doctor_id);

  -- Recreate RLS policies with bigint comparison.
  ALTER TABLE public.verification_requests ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "doctor views own verification" ON public.verification_requests;
  CREATE POLICY "doctor views own verification" ON public.verification_requests
    FOR SELECT TO authenticated
    USING (doctor_id IN (SELECT id FROM public.doctors WHERE owner_user_id = auth.uid()));

  DROP POLICY IF EXISTS "doctor inserts own verification" ON public.verification_requests;
  CREATE POLICY "doctor inserts own verification" ON public.verification_requests
    FOR INSERT TO authenticated
    WITH CHECK (doctor_id IN (SELECT id FROM public.doctors WHERE owner_user_id = auth.uid()));

  DROP POLICY IF EXISTS "admin all verification" ON public.verification_requests;
  CREATE POLICY "admin all verification" ON public.verification_requests
    FOR ALL TO authenticated
    USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
    WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
END $$;
