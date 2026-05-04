-- Fix INSERT grants on reports and ensure doctor_report_totals trigger works.

-- --------------------------------------------------------------------------
-- 1) Ensure doctor_report_totals exists (trigger depends on it)
-- --------------------------------------------------------------------------
create table if not exists public.doctor_report_totals (
  doctor_id integer primary key references public.doctors(id) on delete cascade,
  report_count integer not null default 0 check (report_count >= 0)
);

alter table public.doctor_report_totals disable row level security;

revoke all on public.doctor_report_totals from public;
revoke all on public.doctor_report_totals from anon, authenticated;
grant select on public.doctor_report_totals to anon, authenticated, service_role;

-- Backfill counts from existing reports
insert into public.doctor_report_totals (doctor_id, report_count)
select doctor_id, count(*)::integer
from public.reports
group by doctor_id
on conflict (doctor_id) do update
set report_count = excluded.report_count;

-- --------------------------------------------------------------------------
-- 2) Re-apply INSERT grant + RLS policy on reports
-- --------------------------------------------------------------------------
grant insert on public.reports to anon, authenticated;
grant select on public.reports to service_role, authenticated;

alter table public.reports enable row level security;

drop policy if exists "Anyone can insert reports" on public.reports;
create policy "Anyone can insert reports"
  on public.reports
  for insert
  to anon, authenticated
  with check (true);

-- --------------------------------------------------------------------------
-- 3) Make error_location nullable to avoid NOT NULL issues on insert
-- --------------------------------------------------------------------------
alter table public.reports alter column error_location drop not null;
