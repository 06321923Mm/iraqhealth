-- App "إضافة عيادة" inserts into public.pending_doctors with the anon key.
-- Previously only DELETE was granted (admin); INSERT was missing → RLS/permission failures.

do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'pending_doctors'
  ) then
    return;
  end if;

  execute 'grant insert on table public.pending_doctors to anon';

  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'pending_doctors'
      and c.relrowsecurity
  ) then
    execute $pol$
      drop policy if exists "Anyone can insert pending_doctors" on public.pending_doctors;
      create policy "Anyone can insert pending_doctors"
        on public.pending_doctors
        for insert
        to anon
        with check (true);
    $pol$;
  end if;
end $$;
