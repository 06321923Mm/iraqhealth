-- Doctor coordinates and lightweight location feedback live on public.doctors (single source of truth).
-- RPCs allow anon to adjust only location-related fields without widening general UPDATE semantics.

alter table public.doctors add column if not exists lat double precision;
alter table public.doctors add column if not exists lng double precision;
alter table public.doctors add column if not exists location_correction_count integer not null default 0
  check (location_correction_count >= 0);
alter table public.doctors add column if not exists location_confirmations integer not null default 0
  check (location_confirmations >= 0);

-- Replace column-level UPDATE grant to include new fields (admin + bulk tools use same anon key).
revoke update on public.doctors from anon;
grant update (
  name, spec, addr, ph, ph2, notes,
  lat, lng, location_correction_count, location_confirmations
) on public.doctors to anon;

create or replace function public.increment_doctor_location_confirmations(p_doctor_id integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.doctors
  set location_confirmations = location_confirmations + 1
  where id = p_doctor_id;
end;
$$;

revoke all on function public.increment_doctor_location_confirmations(integer) from public;
grant execute on function public.increment_doctor_location_confirmations(integer) to anon;

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
    lat = p_lat,
    lng = p_lng,
    location_correction_count = location_correction_count + 1
  where id = p_doctor_id;
end;
$$;

revoke all on function public.submit_doctor_location_coordinates(integer, double precision, double precision) from public;
grant execute on function public.submit_doctor_location_coordinates(integer, double precision, double precision) to anon;
