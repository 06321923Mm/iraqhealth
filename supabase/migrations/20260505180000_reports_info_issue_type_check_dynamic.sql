-- Dynamic edit suggestions use info_issue_type values such as
--   field_edit:<column_name>  and  wrong_map_location
-- Older databases may still enforce a short allow-list CHECK; that rejects
-- inserts from lib/edit_suggestion/dynamic_report_insert.dart.

alter table public.reports drop constraint if exists reports_info_issue_type_check;

alter table public.reports
  add constraint reports_info_issue_type_check
  check (char_length(btrim(info_issue_type::text)) > 0);
