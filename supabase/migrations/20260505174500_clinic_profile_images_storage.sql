-- Storage bucket + policies for doctor clinic profile images.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'clinic-profile-images',
  'clinic-profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'clinic profile images public read'
  ) then
    create policy "clinic profile images public read"
      on storage.objects for select
      to public
      using (bucket_id = 'clinic-profile-images');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'clinic profile images authenticated insert own folder'
  ) then
    create policy "clinic profile images authenticated insert own folder"
      on storage.objects for insert
      to authenticated
      with check (
        bucket_id = 'clinic-profile-images'
        and auth.uid() is not null
        and name like auth.uid()::text || '/%'
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'clinic profile images authenticated update own folder'
  ) then
    create policy "clinic profile images authenticated update own folder"
      on storage.objects for update
      to authenticated
      using (
        bucket_id = 'clinic-profile-images'
        and auth.uid() is not null
        and name like auth.uid()::text || '/%'
      )
      with check (
        bucket_id = 'clinic-profile-images'
        and auth.uid() is not null
        and name like auth.uid()::text || '/%'
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'clinic profile images authenticated delete own folder'
  ) then
    create policy "clinic profile images authenticated delete own folder"
      on storage.objects for delete
      to authenticated
      using (
        bucket_id = 'clinic-profile-images'
        and auth.uid() is not null
        and name like auth.uid()::text || '/%'
      );
  end if;
end $$;
