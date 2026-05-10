-- TASK 6: Smart duplicate detection helper for pending_doctors approvals.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION public.find_duplicate_doctor(
  p_name      text,
  p_gove      text,
  p_phone     text,
  p_threshold real DEFAULT 0.8
)
RETURNS TABLE (
  id          integer,
  name        text,
  spec        text,
  gove        text,
  ph          text,
  ph2         text,
  similarity_score real,
  phone_match boolean
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH normalized_phone AS (
    SELECT regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g') AS digits
  ),
  candidates AS (
    SELECT d.id,
           d.name,
           d.spec,
           d.gove,
           d.ph,
           d.ph2,
           similarity(d.name, p_name) AS sim,
           regexp_replace(COALESCE(d.ph,  ''), '\D', '', 'g') AS dn1,
           regexp_replace(COALESCE(d.ph2, ''), '\D', '', 'g') AS dn2
      FROM public.doctors d
     WHERE p_name IS NOT NULL
       AND length(trim(p_name)) >= 2
       AND d.gove = p_gove
       AND similarity(d.name, p_name) > GREATEST(p_threshold, 0.0)
  )
  SELECT c.id,
         c.name,
         c.spec,
         c.gove,
         c.ph,
         c.ph2,
         c.sim AS similarity_score,
         (
           (length((SELECT digits FROM normalized_phone)) >= 6)
           AND (
             c.dn1 LIKE '%' || (SELECT digits FROM normalized_phone) || '%'
             OR c.dn2 LIKE '%' || (SELECT digits FROM normalized_phone) || '%'
             OR (SELECT digits FROM normalized_phone) LIKE '%' || NULLIF(c.dn1, '') || '%'
             OR (SELECT digits FROM normalized_phone) LIKE '%' || NULLIF(c.dn2, '') || '%'
           )
         ) AS phone_match
    FROM candidates c
   ORDER BY c.sim DESC
   LIMIT 5;
$$;

REVOKE ALL ON FUNCTION public.find_duplicate_doctor(text, text, text, real) FROM public;
GRANT EXECUTE ON FUNCTION public.find_duplicate_doctor(text, text, text, real)
  TO authenticated;

CREATE INDEX IF NOT EXISTS doctors_name_trgm_idx
  ON public.doctors USING gin (name gin_trgm_ops);
