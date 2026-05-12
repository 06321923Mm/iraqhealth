-- Lightweight RPC that returns all distinct (spec, area) pairs for a given
-- governorate. Used by the Flutter client to populate filter chips immediately,
-- independently of the paginated doctor list.

CREATE OR REPLACE FUNCTION public.get_doctors_filters(p_gove text)
RETURNS TABLE(spec text, area text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    d.spec,
    d.area
  FROM public.doctors d
  WHERE d.gove = p_gove
    AND d.spec IS NOT NULL AND d.spec <> ''
    AND d.area IS NOT NULL AND d.area <> ''
  ORDER BY d.spec, d.area;
$$;

REVOKE ALL ON FUNCTION public.get_doctors_filters(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_doctors_filters(text) TO anon, authenticated;
