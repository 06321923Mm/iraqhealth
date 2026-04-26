-- صلاحيات CRUD للأدمن (مفتاح anon) على جدولَي doctors و pending_doctors.
-- يُصلح: فشل الموافقة (INSERT doctors) وفشل الحذف (DELETE pending_doctors).

-- ---------------------------------------------------------------------------
-- doctors: INSERT للأدمن لإضافة عيادة عند الموافقة على طلب انتظار
-- ---------------------------------------------------------------------------
grant insert on public.doctors to anon;

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
      drop policy if exists "Anon admin can insert doctors" on public.doctors;
      create policy "Anon admin can insert doctors"
        on public.doctors
        for insert
        to anon
        with check (true);
    $q$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- pending_doctors: DELETE للأدمن للموافقة أو الرفض على الطلبات
-- ---------------------------------------------------------------------------
grant delete on public.pending_doctors to anon;

do $$
begin
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'pending_doctors'
      and c.relrowsecurity
  ) then
    execute $q$
      drop policy if exists "Anon admin can delete pending_doctors" on public.pending_doctors;
      create policy "Anon admin can delete pending_doctors"
        on public.pending_doctors
        for delete
        to anon
        using (true);
    $q$;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- reports: إضافة عمود doctor_name إن لم يكن موجوداً (لعرضه في لوحة الأدمن)
-- ---------------------------------------------------------------------------
alter table public.reports add column if not exists doctor_name text;
