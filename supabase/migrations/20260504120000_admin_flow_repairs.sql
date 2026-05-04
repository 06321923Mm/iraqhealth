-- إصلاحات لوحة الأدمن: CHECK على status، بحث الأطباء العربي، GRANTs ناقصة.
-- آمنة للتشغيل المتكرر (idempotent).

-- ---------------------------------------------------------------------------
-- 1) reports.status: توحيد القيم مع الكود (pending, reviewed, resolved, dismissed)
-- ---------------------------------------------------------------------------
-- ترحيل أي قيم قديمة محتملة من الإصدار السابق (approved/rejected) إلى الجديدة.
update public.reports
set status = case
  when status = 'approved' then 'resolved'
  when status = 'rejected' then 'dismissed'
  else status
end
where status in ('approved', 'rejected');

alter table public.reports drop constraint if exists reports_status_check;

alter table public.reports
  add constraint reports_status_check
  check (status in ('pending', 'reviewed', 'resolved', 'dismissed'));

-- ---------------------------------------------------------------------------
-- 2) بحث عربي على doctors: عمود محسوب + دالتان + فهرس GIN
--    (مكرر بشكل آمن — قد تكون سابقة فشلت جزئياً فبقيت الكائنات مفقودة)
-- ---------------------------------------------------------------------------
create extension if not exists pg_trgm;

create or replace function public.normalize_arabic_search_text(src text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  s text;
  parts text[];
  i int;
  w text;
  n int;
begin
  if src is null then
    return '';
  end if;
  s := trim(both from regexp_replace(src, '\s+', ' ', 'g'));
  if s = '' then
    return '';
  end if;
  s := replace(replace(replace(replace(s, 'أ', 'ا'), 'إ', 'ا'), 'آ', 'ا'), 'ٱ', 'ا');
  s := replace(s, 'ى', 'ي');
  parts := regexp_split_to_array(s, ' ');
  n := coalesce(array_length(parts, 1), 0);
  if n > 0 then
    for i in 1..n loop
      w := parts[i];
      if w ~ 'ة$' then
        parts[i] := substring(w from 1 for char_length(w) - 1) || 'ه';
      end if;
    end loop;
    s := array_to_string(parts, ' ');
  end if;
  if s ~ '^(عبد|أبو|أم) ' then
    s := regexp_replace(s, '^(عبد|أبو|أم) (.*)$', '\1\2');
  end if;
  s := trim(both from regexp_replace(s, '\s+', ' ', 'g'));
  return lower(s);
end;
$$;

comment on function public.normalize_arabic_search_text(text) is
  'تطبيع للبحث: أإآ→ا، ى→ي، ة نهاية الكلمة→ه، دمج مسافة بعد عبد/أبو/أم في بداية النص.';

-- عمود محسوب؛ نتفادى خطأ "already exists" عبر فحص مسبق.
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'doctors'
      and column_name = 'search_document'
  ) then
    execute $sql$
      alter table public.doctors
        add column search_document text
        generated always as (
          public.normalize_arabic_search_text(coalesce(name, ''))
          || ' '
          || public.normalize_arabic_search_text(coalesce(spec, ''))
          || ' '
          || public.normalize_arabic_search_text(coalesce(area, ''))
          || ' '
          || public.normalize_arabic_search_text(coalesce(addr, ''))
        ) stored
    $sql$;
  end if;
end $$;

create index if not exists doctors_search_document_trgm_idx
  on public.doctors using gin (search_document gin_trgm_ops);

create or replace function public.search_doctors_by_tokens(tokens text[])
returns setof public.doctors
language sql
stable
set search_path = public
as $$
  select d.*
  from public.doctors d
  where tokens is not null
    and cardinality(tokens) > 0
    and not exists (
      select 1
      from unnest(tokens) as tok(t)
      where btrim(t) = ''
         or position(btrim(t) in d.search_document) = 0
    )
  order by d.id asc
  limit 30;
$$;

comment on function public.search_doctors_by_tokens(text[]) is
  'بحث أطباء: كلمات مطبّعة من التطبيق؛ تطابق جزئي (substring) على search_document.';

revoke all on function public.normalize_arabic_search_text(text) from public;
grant execute on function public.normalize_arabic_search_text(text) to anon, authenticated;

revoke all on function public.search_doctors_by_tokens(text[]) from public;
grant execute on function public.search_doctors_by_tokens(text[]) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) توسيع UPDATE للـ anon على doctors ليشمل area و gove
--    (مطلوب لتطبيق اقتراحات تعديل هذين الحقلَين من لوحة الأدمن)
-- ---------------------------------------------------------------------------
grant update (area, gove) on public.doctors to anon;
