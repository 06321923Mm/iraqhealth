-- Align public.doctors coordinate columns with API names latitude / longitude.
-- Keeps RPC parameter names (p_lat, p_lng) for app compatibility.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'lat'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'latitude'
  ) then
    alter table public.doctors rename column lat to latitude;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'lng'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'longitude'
  ) then
    alter table public.doctors rename column lng to longitude;
  end if;
end $$;

-- Optional coordinates on pending clinic requests (nullable until user picks on map).
alter table public.pending_doctors add column if not exists latitude double precision;
alter table public.pending_doctors add column if not exists longitude double precision;

create or replace function public.submit_doctor_location_coordinates(
  p_doctor_id integer,
  p_lat double precision,
  p_lng double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.doctors
  set
    latitude = p_lat,
    longitude = p_lng,
    location_correction_count = location_correction_count + 1
  where id = p_doctor_id;
end;
$$;

revoke update on public.doctors from anon;

grant update (
  name, spec, addr, ph, ph2, notes,
  latitude, longitude, location_correction_count, location_confirmations
) on public.doctors to anon;
