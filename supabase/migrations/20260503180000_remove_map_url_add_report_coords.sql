-- إزالة عمود رابط الخرائط إن وُجد؛ إضافة إحداثيات مقترحة لتقارير تصحيح الموقع.

alter table public.doctors drop column if exists map_url;
alter table public.pending_doctors drop column if exists map_url;
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
