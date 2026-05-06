-- STEP 1.4 — Private storage bucket for verification documents

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'verification-docs',
  'verification-docs',
  FALSE,
  10485760,  -- 10 MB per file
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE
SET
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Authenticated users can upload only into their own folder
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage'
      AND tablename='objects' AND policyname='verification docs owner upload'
  ) THEN
    CREATE POLICY "verification docs owner upload"
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'verification-docs'
        AND auth.uid() IS NOT NULL
        AND name LIKE auth.uid()::text || '/%'
      );
  END IF;
END $$;

-- Owner can read their own files
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage'
      AND tablename='objects' AND policyname='verification docs owner read'
  ) THEN
    CREATE POLICY "verification docs owner read"
      ON storage.objects FOR SELECT
      TO authenticated
      USING (
        bucket_id = 'verification-docs'
        AND name LIKE auth.uid()::text || '/%'
      );
  END IF;
END $$;

-- Owner can delete their own files
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage'
      AND tablename='objects' AND policyname='verification docs owner delete'
  ) THEN
    CREATE POLICY "verification docs owner delete"
      ON storage.objects FOR DELETE
      TO authenticated
      USING (
        bucket_id = 'verification-docs'
        AND name LIKE auth.uid()::text || '/%'
      );
  END IF;
END $$;

-- Anon admin can read all verification docs for review
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage'
      AND tablename='objects' AND policyname='verification docs anon admin read all'
  ) THEN
    CREATE POLICY "verification docs anon admin read all"
      ON storage.objects FOR SELECT
      TO anon
      USING (bucket_id = 'verification-docs');
  END IF;
END $$;
