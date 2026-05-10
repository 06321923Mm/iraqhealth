-- TASK 4: BlurHash placeholder column for clinic profile images.

ALTER TABLE public.doctors
  ADD COLUMN IF NOT EXISTS image_blurhash text;

COMMENT ON COLUMN public.doctors.image_blurhash IS
  'BlurHash string used as a low-fidelity placeholder while profile_image_url loads.';
