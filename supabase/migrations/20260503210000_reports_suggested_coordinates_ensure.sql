-- Ensure public.reports has suggested map coordinates for wrong_map_location (Flutter: buildReportRowPayload).
-- Idempotent: safe if 20260503180000_remove_map_url_add_report_coords.sql already ran.

alter table public.reports drop column if exists map_url;

alter table public.reports add column if not exists suggested_latitude double precision;
alter table public.reports add column if not exists suggested_longitude double precision;

comment on column public.reports.suggested_latitude is
  'When info_issue_type = wrong_map_location: latitude proposed by reporter.';
comment on column public.reports.suggested_longitude is
  'When info_issue_type = wrong_map_location: longitude proposed by reporter.';

update public.reports
set info_issue_type = 'wrong_map_location'
where info_issue_type = 'wrong_map_link';
