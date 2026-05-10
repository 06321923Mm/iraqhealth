-- TASK 1: Canonical specializations + suggestion RPC
-- Idempotent and safe to run multiple times.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS public.specializations (
  id              integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  canonical_name  text    UNIQUE NOT NULL,
  display_names   text[]  NOT NULL DEFAULT '{}',
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Trigram index for similarity() filtering.
CREATE INDEX IF NOT EXISTS specializations_canonical_trgm_idx
  ON public.specializations USING gin (canonical_name gin_trgm_ops);

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS specialization_id integer
    REFERENCES public.specializations(id) ON DELETE SET NULL;

ALTER TABLE public.pending_doctors
  ADD COLUMN IF NOT EXISTS specialization_id integer
    REFERENCES public.specializations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS doctors_specialization_id_idx
  ON public.doctors (specialization_id);
CREATE INDEX IF NOT EXISTS pending_doctors_specialization_id_idx
  ON public.pending_doctors (specialization_id);

-- Seed from existing kPhysicianSpecializations + canonical group labels.
INSERT INTO public.specializations (canonical_name) VALUES
  ('النسائية'),
  ('الباطنية'),
  ('جراحة عامه'),
  ('اختصاص الأطفال'),
  ('الكسور و المفاصل'),
  ('الجلدية و التجميلية'),
  ('الاذن و الانف و الحنجرة'),
  ('تخصصات اخرى'),
  ('طب وجراحة العيون'),
  ('الجملة العصبية'),
  ('عوينات لفحص البصر'),
  ('القلبية'),
  ('جراحة المجاري البولية'),
  ('مراكز التجميل والليزر'),
  ('المجمعات الطبية الخيرية'),
  ('تجهيزات طبية'),
  ('الباطنية - الأورام والغدد'),
  ('اختصاص التغذية'),
  ('المستشفيات الاهلية في البصرة'),
  ('الباطنية - غدد الصماء والسكري'),
  ('النفسية'),
  ('أختصاص التخدير'),
  ('الباطنية - أمراض الدم'),
  ('عيادات الفسلجة العصبية لتخطيط الاعصاب والعضلات والدماغ'),
  ('الباطنية - أمراض الكلى'),
  ('الباطنية - الجهاز الهضمي'),
  ('مراكز العقيم وأطفال الانابيب'),
  ('مراكز الطب النووي فحوصات البتا سكان'),
  ('طب وتجميل الاسنان'),
  ('الصيدليات'),
  ('المختبرات الطبية'),
  ('الاشعة والسونار')
ON CONFLICT (canonical_name) DO NOTHING;

-- Backfill specialization_id by exact spec match where possible.
UPDATE public.doctors d
   SET specialization_id = s.id
  FROM public.specializations s
 WHERE d.specialization_id IS NULL
   AND TRIM(d.spec) = s.canonical_name;

UPDATE public.pending_doctors p
   SET specialization_id = s.id
  FROM public.specializations s
 WHERE p.specialization_id IS NULL
   AND TRIM(p.spec) = s.canonical_name;

-- Suggest function: top 3 fuzzy matches.
CREATE OR REPLACE FUNCTION public.suggest_specialization(input_text text)
RETURNS TABLE (id integer, canonical_name text, similarity_score real)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT s.id,
         s.canonical_name,
         similarity(s.canonical_name, input_text) AS similarity_score
    FROM public.specializations s
   WHERE input_text IS NOT NULL
     AND length(trim(input_text)) >= 1
     AND similarity(s.canonical_name, input_text) > 0.3
   ORDER BY similarity_score DESC
   LIMIT 3;
$$;

REVOKE ALL ON FUNCTION public.suggest_specialization(text) FROM public;
GRANT EXECUTE ON FUNCTION public.suggest_specialization(text) TO anon, authenticated;

ALTER TABLE public.specializations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "specializations readable by all" ON public.specializations;
CREATE POLICY "specializations readable by all"
  ON public.specializations FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "specializations insert by authenticated" ON public.specializations;
CREATE POLICY "specializations insert by authenticated"
  ON public.specializations FOR INSERT
  TO authenticated
  WITH CHECK (true);

GRANT SELECT ON public.specializations TO anon, authenticated;
GRANT INSERT ON public.specializations TO authenticated;
