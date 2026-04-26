-- Reports about doctors. Run against your Supabase project (SQL editor or: supabase db push).
-- If an older "reports" table with a different shape already exists, back up data, drop that table, then re-run this migration.

-- ---------------------------------------------------------------------------
-- reports
-- ---------------------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  doctor_id integer not null references public.doctors (id) on delete cascade,
  info_issue_type text not null,
  error_location text not null,
  suggested_correction text not null,
  status text not null default 'pending'
    check (status in ('pending', 'reviewed', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reports_doctor_id_idx on public.reports (doctor_id);
create index if not exists reports_status_idx on public.reports (status);
create index if not exists reports_created_at_idx on public.reports (created_at desc);

-- ---------------------------------------------------------------------------
-- Per-doctor report counts (readable by anonymous clients without exposing
-- private report content from public.reports)
-- ---------------------------------------------------------------------------
create table if not exists public.doctor_report_totals (
  doctor_id integer primary key references public.doctors (id) on delete cascade,
  report_count integer not null default 0
    check (report_count >= 0)
);

-- ---------------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists reports_set_updated_at on public.reports;
create trigger reports_set_updated_at
  before update on public.reports
  for each row
  execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Keep doctor_report_totals in sync
-- ---------------------------------------------------------------------------
create or replace function public._increment_doctor_report_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.doctor_report_totals (doctor_id, report_count)
  values (new.doctor_id, 1)
  on conflict (doctor_id) do update
  set report_count = public.doctor_report_totals.report_count + 1;
  return new;
end;
$$;

create or replace function public._decrement_doctor_report_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.doctor_report_totals
  set report_count = greatest(0, report_count - 1)
  where doctor_id = old.doctor_id;
  return old;
end;
$$;

create or replace function public._move_doctor_report_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.doctor_id is distinct from new.doctor_id then
    update public.doctor_report_totals
    set report_count = greatest(0, report_count - 1)
    where doctor_id = old.doctor_id;
    insert into public.doctor_report_totals (doctor_id, report_count)
    values (new.doctor_id, 1)
    on conflict (doctor_id) do update
    set report_count = public.doctor_report_totals.report_count + 1;
  end if;
  return new;
end;
$$;

drop trigger if exists reports_after_insert_bump on public.reports;
create trigger reports_after_insert_bump
  after insert on public.reports
  for each row
  execute procedure public._increment_doctor_report_total();

drop trigger if exists reports_after_delete_bump on public.reports;
create trigger reports_after_delete_bump
  after delete on public.reports
  for each row
  execute procedure public._decrement_doctor_report_total();

drop trigger if exists reports_after_update_move on public.reports;
create trigger reports_after_update_move
  after update of doctor_id on public.reports
  for each row
  execute procedure public._move_doctor_report_total();

-- Backfill counts from any existing report rows
insert into public.doctor_report_totals (doctor_id, report_count)
select doctor_id, count(*)::integer
from public.reports
group by doctor_id
on conflict (doctor_id) do update
set report_count = excluded.report_count;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.reports enable row level security;
-- Totals: protect via GRANT/REVOKE only so trigger-owned writes always succeed
alter table public.doctor_report_totals disable row level security;

drop policy if exists "Anyone can insert reports" on public.reports;
create policy "Anyone can insert reports"
  on public.reports
  for insert
  to anon, authenticated
  with check (true);

-- No SELECT on individual reports for anonymous users (use totals table for counts)
drop policy if exists "Service role can read all reports" on public.reports;
create policy "Service role can read all reports"
  on public.reports
  for select
  to service_role
  using (true);

-- Authenticated (e.g. future admin) read — optional; tighten later with auth
drop policy if exists "Authenticated can read reports" on public.reports;
create policy "Authenticated can read reports"
  on public.reports
  for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- Grants (defaults may grant too much; lock down totals to SELECT for API roles)
-- ---------------------------------------------------------------------------
revoke all on public.doctor_report_totals from public;
revoke all on public.doctor_report_totals from anon, authenticated;
grant select on public.doctor_report_totals to anon, authenticated, service_role;

revoke all on public.reports from public;
grant insert on public.reports to anon, authenticated;
grant select on public.reports to service_role, authenticated;
