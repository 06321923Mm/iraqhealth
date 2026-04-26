-- Reassert reports.status CHECK so it matches the app and RLS policy
-- (pending, reviewed, resolved, dismissed). Use this if an older database
-- had a different CHECK and rejects updates with PostgresException
-- "violating check constraint reports_status_check".

alter table public.reports drop constraint if exists reports_status_check;

alter table public.reports
  add constraint reports_status_check
  check (status in ('pending', 'reviewed', 'resolved', 'dismissed'));
