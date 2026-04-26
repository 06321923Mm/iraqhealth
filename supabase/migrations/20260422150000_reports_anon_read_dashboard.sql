-- اختياري: للسماح لتطبيق الأدمن (مفتاح anon) بقراءة اقتراحات التعديل في لوحة التحكم.
-- طبّقه فقط إن كنت تريد عرض جدول reports في التطبيق مع نفس مفتاح anon.
-- راجع المخاطر: أي عميل بمفتاح anon يستطيع قراءة محتوى الاقتراحات.

drop policy if exists "Allow anon read reports for in-app admin list" on public.reports;
create policy "Allow anon read reports for in-app admin list"
  on public.reports
  for select
  to anon
  using (true);
