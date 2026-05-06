-- Optional profile image URL for doctor clinic profile.
alter table public.doctors
  add column if not exists profile_image_url text;

comment on column public.doctors.profile_image_url is
  'Optional public URL for doctor/clinic profile image.';
