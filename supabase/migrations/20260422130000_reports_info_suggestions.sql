-- public.reports: اقتراحات تصحيح المعلومات (يسمح للعم بتحديد مكان الخطأ والصح)
-- ينفَّذ بعد migration إنشاء جدول reports. إن وُجد العمودان reason و description
-- ينسخان تلقائياً ثم يُحذفان.

alter table public.reports add column if not exists info_issue_type text;
alter table public.reports add column if not exists error_location text;
alter table public.reports add column if not exists suggested_correction text;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reports'
      and column_name = 'reason'
  ) then
    update public.reports
    set
      info_issue_type = coalesce(
        nullif(btrim(info_issue_type), ''),
        nullif(btrim(reason), ''),
        'other'
      ),
      error_location = coalesce(
        nullif(btrim(error_location), ''),
        'غير محدد (سجل سابق)'
      ),
      suggested_correction = coalesce(
        nullif(btrim(suggested_correction), ''),
        nullif(btrim(description), ''),
        '—'
      );
  else
    update public.reports
    set
      info_issue_type = coalesce(nullif(btrim(info_issue_type), ''), 'other'),
      error_location = coalesce(nullif(btrim(error_location), ''), 'غير محدد'),
      suggested_correction = coalesce(nullif(btrim(suggested_correction), ''), '—');
  end if;
end $$;

alter table public.reports drop column if exists reason;
alter table public.reports drop column if exists description;

alter table public.reports
  alter column info_issue_type set not null,
  alter column error_location set not null,
  alter column suggested_correction set not null;

comment on column public.reports.info_issue_type is
  'e.g. wrong_phone, wrong_map_link — information only';
comment on column public.reports.error_location is
  'Where the wrong data appears in the card';
comment on column public.reports.suggested_correction is
  'Proposed correct information';
