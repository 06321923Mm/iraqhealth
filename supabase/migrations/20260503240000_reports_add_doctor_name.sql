-- public.reports: إضافة عمود doctor_name (مطلوب من buildReportRowPayload في Flutter).
-- آمن للتكرار (idempotent).

alter table public.reports add column if not exists doctor_name text not null default '';

comment on column public.reports.doctor_name is
  'Snapshot of the doctor name at the time of report submission.';
