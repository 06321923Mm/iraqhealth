-- صلاحيات UPDATE للأدمن (مفتاح anon) على جدولَي reports و doctors.
-- يتيح لوحة الأدمن تطبيق التصحيحات على جدول الأطباء وتغيير status الاقتراحات.

-- ---------------------------------------------------------------------------
-- reports: السماح لـ anon بتحديث حقل status فقط
-- ---------------------------------------------------------------------------
grant update (status) on public.reports to anon;

drop policy if exists "Anon admin can update report status" on public.reports;
create policy "Anon admin can update report status"
  on public.reports
  for update
  to anon
  using (true)
  with check (status in ('pending', 'reviewed', 'resolved', 'dismissed'));

-- ---------------------------------------------------------------------------
-- doctors: السماح لـ anon بتحديث حقول البيانات (التصحيح من الأدمن)
-- ---------------------------------------------------------------------------
grant update (name, spec, addr, ph, ph2, notes) on public.doctors to anon;

-- إن كانت RLS مفعّلة على جدول doctors أضف السياسة أدناه، وإلا يكفي الـ GRANT.
do $$
begin
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'doctors'
      and c.relrowsecurity
  ) then
    execute $q$
      drop policy if exists "Anon admin can update doctor fields" on public.doctors;
      create policy "Anon admin can update doctor fields"
        on public.doctors
        for update
        to anon
        using (true)
        with check (true);
    $q$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- doctor_report_totals: صلاحية upsert للـ anon لمزامنة العداد عند resolve/dismiss
-- (RLS معطّلة على هذا الجدول، لذا GRANT وحده كافٍ)
-- ---------------------------------------------------------------------------
grant insert, update on public.doctor_report_totals to anon;
