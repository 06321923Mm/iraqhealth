-- TASK 2: Keyset pagination RPC for doctors by gove + composite index.

CREATE INDEX IF NOT EXISTS doctors_gove_id_idx
  ON public.doctors (gove, id);

CREATE OR REPLACE FUNCTION public.get_doctors_page_keyset(
  p_gove    text,
  p_limit   int DEFAULT 30,
  p_last_id int DEFAULT 0
)
RETURNS SETOF public.doctors
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT *
    FROM public.doctors
   WHERE gove = p_gove
     AND id > p_last_id
   ORDER BY id ASC
   LIMIT GREATEST(p_limit, 1);
$$;

REVOKE ALL ON FUNCTION public.get_doctors_page_keyset(text, int, int) FROM public;
GRANT EXECUTE ON FUNCTION public.get_doctors_page_keyset(text, int, int)
  TO anon, authenticated;
