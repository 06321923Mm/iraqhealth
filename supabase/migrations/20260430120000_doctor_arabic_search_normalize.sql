-- بحث عربي مرن: تطبيع يطابق منطق التطبيق (lib/arabic_search_normalize.dart)
-- + عمود محسوب للبحث السريع + دالة RPC للوحة الأدمن.

create extension if not exists pg_trgm;

-- تطبيع نص واحد (أسماء/تخصصات قبل الدمج في search_document)
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
  for i in 1..n loop
    w := parts[i];
    if w ~ 'ة$' then
      parts[i] := substring(w from 1 for char_length(w) - 1) || 'ه';
    end if;
  end loop;
  s := array_to_string(parts, ' ');
  if s ~ '^(عبد|أبو|أم) ' then
    s := regexp_replace(s, '^(عبد|أبو|أم) (.*)$', '\1\2');
  end if;
  s := trim(both from regexp_replace(s, '\s+', ' ', 'g'));
  return lower(s);
end;
$$;

comment on function public.normalize_arabic_search_text(text) is
  'تطبيع للبحث: أإآ→ا، ى→ي، ة نهاية الكلمة→ه، دمج مسافة بعد عبد/أبو/أم في بداية النص.';

-- عمود محسوب: حقول البحث مجمّعة ومطبّعة (AND للكلمات يتم في دالة البحث)
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
  ) stored;

create index if not exists doctors_search_document_trgm_idx
  on public.doctors using gin (search_document gin_trgm_ops);

-- بحث بالكلمات: كل كلمة مستقلة، ترتيب غير مهم (AND)، أي حقل يكفي لكل كلمة
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

grant execute on function public.normalize_arabic_search_text(text) to anon;
grant execute on function public.normalize_arabic_search_text(text) to authenticated;
grant execute on function public.search_doctors_by_tokens(text[]) to anon;
grant execute on function public.search_doctors_by_tokens(text[]) to authenticated;
