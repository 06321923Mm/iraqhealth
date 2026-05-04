-- =============================================================================
-- Apply this file manually on Supabase:
--   Dashboard -> SQL Editor -> New query -> paste all -> Run
--
-- Includes migrations:
--   20260503120000_doctors_latitude_longitude
--   20260503180000_remove_map_url_add_report_coords
--   20260503200000_coordinate_flow_rls_grants
--   20260503210000_reports_suggested_coordinates_ensure
--   20260503230000_pending_doctors_anon_insert
--   20260503240000_reports_add_doctor_name
--   20260504100000_edit_suggestion_schema_introspection
--
-- Idempotent (safe to run multiple times).
-- =============================================================================

-- --------------------------------------------------------------------------
-- 1) doctors: rename lat/lng -> latitude/longitude if needed
-- --------------------------------------------------------------------------
do $do1$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'lat'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'latitude'
  ) then
    alter table public.doctors rename column lat to latitude;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'lng'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'doctors' and column_name = 'longitude'
  ) then
    alter table public.doctors rename column lng to longitude;
  end if;
end $do1$;

-- --------------------------------------------------------------------------
-- 2) pending_doctors: add coordinate columns if table exists
-- --------------------------------------------------------------------------
do $do2$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'pending_doctors'
  ) then
    alter table public.pending_doctors add column if not exists latitude double precision;
    alter table public.pending_doctors add column if not exists longitude double precision;
  end if;
end $do2$;

-- --------------------------------------------------------------------------
-- 3) RPC: submit_doctor_location_coordinates
-- --------------------------------------------------------------------------
create or replace function public.submit_doctor_location_coordinates(
  p_doctor_id integer,
  p_lat double precision,
  p_lng double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $fn1$
begin
  update public.doctors
  set
    latitude = p_lat,
    longitude = p_lng,
    location_correction_count = location_correction_count + 1
  where id = p_doctor_id;
end;
$fn1$;

revoke all on function public.submit_doctor_location_coordinates(integer, double precision, double precision) from public;
grant execute on function public.submit_doctor_location_coordinates(integer, double precision, double precision) to anon;

revoke update on public.doctors from anon;
grant update (
  name, spec, addr, ph, ph2, notes,
  latitude, longitude, location_correction_count, location_confirmations
) on public.doctors to anon;

-- --------------------------------------------------------------------------
-- 4) Remove map_url; add suggested coords to reports
-- --------------------------------------------------------------------------
alter table public.doctors drop column if exists map_url;

do $do3$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'pending_doctors'
  ) then
    alter table public.pending_doctors drop column if exists map_url;
  end if;
end $do3$;

alter table public.reports drop column if exists map_url;

alter table public.reports add column if not exists suggested_latitude double precision;
alter table public.reports add column if not exists suggested_longitude double precision;

comment on column public.reports.suggested_latitude is
  'When info_issue_type = wrong_map_location: latitude proposed by reporter.';
comment on column public.reports.suggested_longitude is
  'When info_issue_type = wrong_map_location: longitude proposed by reporter.';

update public.reports
set info_issue_type = 'wrong_map_location'
where info_issue_type = 'wrong_map_link';

-- --------------------------------------------------------------------------
-- 4b) pending_doctors: grant INSERT to anon
-- --------------------------------------------------------------------------
do $do4$
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
    execute 'drop policy if exists "Anyone can insert pending_doctors" on public.pending_doctors';
    execute 'create policy "Anyone can insert pending_doctors"
      on public.pending_doctors
      for insert
      to anon
      with check (true)';
  end if;
end $do4$;

-- --------------------------------------------------------------------------
-- 5) reports: add doctor_name column
-- --------------------------------------------------------------------------
alter table public.reports add column if not exists doctor_name text not null default '';

comment on column public.reports.doctor_name is
  'Snapshot of the doctor name at the time of report submission.';

-- --------------------------------------------------------------------------
-- 6) reports: generic columns for dynamic edit suggestion form
-- --------------------------------------------------------------------------
alter table public.reports add column if not exists target_type text;
alter table public.reports add column if not exists field_name  text;
alter table public.reports add column if not exists new_value   jsonb;
alter table public.reports add column if not exists metadata    jsonb;

comment on column public.reports.target_type is 'Logical entity type (usually the referenced table name).';
comment on column public.reports.field_name  is 'Target column the reporter wants to correct.';
comment on column public.reports.new_value   is 'Structured proposed value (text, uuid, or coordinates).';
comment on column public.reports.metadata    is 'Optional JSON for client extensions.';

-- --------------------------------------------------------------------------
-- 7a) RPC: app_list_table_columns
-- --------------------------------------------------------------------------
create or replace function public.app_list_table_columns(
  p_schema text,
  p_table  text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $fn_list_cols$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'column_name',  c.column_name,
        'data_type',    c.data_type,
        'udt_name',     c.udt_name,
        'is_nullable',  c.is_nullable,
        'is_primary_key', (pk.column_name is not null),
        'fk_ref_schema',  fk.fk_ref_schema,
        'fk_ref_table',   fk.fk_ref_table,
        'fk_ref_column',  fk.fk_ref_column,
        'description',    dsc.description
      )
      order by c.ordinal_position
    ),
    '[]'::jsonb
  )
  from information_schema.columns c
  left join lateral (
    select pg_catalog.col_description(a.attrelid, a.attnum) as description
    from pg_attribute a
    join pg_class     cl on cl.oid = a.attrelid
    join pg_namespace n  on n.oid  = cl.relnamespace
    where n.nspname   = c.table_schema
      and cl.relname  = c.table_name
      and a.attname   = c.column_name
      and a.attnum    > 0
      and not a.attisdropped
    limit 1
  ) dsc on true
  left join lateral (
    select kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_schema = kcu.constraint_schema
     and tc.constraint_name   = kcu.constraint_name
    where tc.table_schema   = c.table_schema
      and tc.table_name     = c.table_name
      and tc.constraint_type = 'PRIMARY KEY'
      and kcu.column_name   = c.column_name
    limit 1
  ) pk on true
  left join lateral (
    select
      sch2.nspname::text  as fk_ref_schema,
      cl2.relname::text   as fk_ref_table,
      a2.attname::text    as fk_ref_column
    from pg_constraint con
    join pg_class     cl1  on cl1.oid  = con.conrelid
    join pg_namespace sch1 on sch1.oid = cl1.relnamespace
    join unnest(con.conkey, con.confkey) as u(src_att, dst_att) on true
    join pg_attribute a1
      on a1.attrelid = con.conrelid
     and a1.attnum   = u.src_att
     and a1.attname  = c.column_name
    join pg_class     cl2  on cl2.oid  = con.confrelid
    join pg_namespace sch2 on sch2.oid = cl2.relnamespace
    join pg_attribute a2
      on a2.attrelid = con.confrelid
     and a2.attnum   = u.dst_att
    where sch1.nspname::text = c.table_schema
      and cl1.relname::text  = c.table_name
      and con.contype = 'f'
    limit 1
  ) fk on true
  where c.table_schema = p_schema
    and c.table_name   = p_table;
$fn_list_cols$;

revoke all on function public.app_list_table_columns(text, text) from public;
grant execute on function public.app_list_table_columns(text, text) to anon, authenticated;

-- --------------------------------------------------------------------------
-- 7b) RPC: app_fk_label_options
-- --------------------------------------------------------------------------
create or replace function public.app_fk_label_options(
  p_ref_schema   text,
  p_ref_table    text,
  p_pk_column    text,
  p_label_column text,
  p_search       text,
  p_limit        integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn_fk_opts$
declare
  v_ok  boolean;
  v_sql text;
  v_out jsonb;
  v_lim integer := greatest(1, least(coalesce(p_limit, 40), 200));
begin
  select exists (
    select 1
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.table_schema    = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.table_schema    = tc.table_schema
    where tc.table_schema   = 'public'
      and tc.table_name     = 'reports'
      and tc.constraint_type = 'FOREIGN KEY'
      and ccu.table_schema  = p_ref_schema
      and ccu.table_name    = p_ref_table
      and ccu.column_name   = p_pk_column
  )
  into v_ok;

  if not coalesce(v_ok, false) then
    return '[]'::jsonb;
  end if;

  if not exists (
    select 1
    from information_schema.columns c1
    join information_schema.columns c2
      on c1.table_schema = c2.table_schema
     and c1.table_name   = c2.table_name
    where c1.table_schema = p_ref_schema
      and c1.table_name   = p_ref_table
      and c1.column_name  = p_pk_column
      and c2.column_name  = p_label_column
  ) then
    return '[]'::jsonb;
  end if;

  v_sql := format(
    'select coalesce(jsonb_agg(jsonb_build_object(''id'', q.pk::text, ''label'', q.lb)), ''[]''::jsonb)
     from (
       select %I as pk, %I::text as lb
       from %I.%I
       where (($1)::text = '''' or %I::text ilike ''%%'' || ($1)::text || ''%%'')
       order by lb
       limit %s
     ) q',
    p_pk_column, p_label_column,
    p_ref_schema, p_ref_table,
    p_label_column, v_lim
  );

  execute v_sql into v_out using coalesce(p_search, '');
  return coalesce(v_out, '[]'::jsonb);
end;
$fn_fk_opts$;

revoke all on function public.app_fk_label_options(text, text, text, text, text, integer) from public;
grant execute on function public.app_fk_label_options(text, text, text, text, text, integer)
  to anon, authenticated;

-- --------------------------------------------------------------------------
-- 7c) RPC: app_edit_suggestion_schema_bundle
-- --------------------------------------------------------------------------
create or replace function public.app_edit_suggestion_schema_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn_bundle$
declare
  v_reports_exists boolean;
  v_reports_cols   jsonb;
  v_fk             record;
  v_ref_cols       jsonb;
  v_label_col      text;
begin
  select exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reports'
      and c.relkind = 'r'
  )
  into v_reports_exists;

  if not coalesce(v_reports_exists, false) then
    return jsonb_build_object(
      'ok',    false,
      'error', 'reports table not found in schema public'
    );
  end if;

  v_reports_cols := public.app_list_table_columns('public', 'reports');

  select
    kcu.column_name  as fk_column,
    ccu.table_schema as ref_schema,
    ccu.table_name   as ref_table,
    ccu.column_name  as ref_pk_column
  into v_fk
  from information_schema.table_constraints tc
  join information_schema.key_column_usage kcu
    on tc.constraint_name = kcu.constraint_name
   and tc.table_schema    = kcu.table_schema
  join information_schema.constraint_column_usage ccu
    on ccu.constraint_name = tc.constraint_name
   and ccu.table_schema    = tc.table_schema
  where tc.table_schema   = 'public'
    and tc.table_name     = 'reports'
    and tc.constraint_type = 'FOREIGN KEY'
  order by tc.constraint_name, kcu.ordinal_position
  limit 1;

  if v_fk is null then
    return jsonb_build_object(
      'ok',      true,
      'reports', jsonb_build_object(
        'schema',  'public',
        'table',   'reports',
        'columns', v_reports_cols
      ),
      'targets', '[]'::jsonb
    );
  end if;

  v_ref_cols := public.app_list_table_columns(v_fk.ref_schema, v_fk.ref_table);

  select c.column_name
  into v_label_col
  from information_schema.columns c
  where c.table_schema = v_fk.ref_schema
    and c.table_name   = v_fk.ref_table
    and c.column_name <> v_fk.ref_pk_column
    and c.data_type in ('text', 'character varying')
  order by case c.column_name
    when 'name'  then 0
    when 'title' then 1
    else 2
  end, c.ordinal_position
  limit 1;

  return jsonb_build_object(
    'ok',      true,
    'reports', jsonb_build_object(
      'schema',  'public',
      'table',   'reports',
      'columns', v_reports_cols
    ),
    'targets', jsonb_build_array(
      jsonb_build_object(
        'fk_column',            v_fk.fk_column,
        'ref_schema',           v_fk.ref_schema,
        'ref_table',            v_fk.ref_table,
        'pk_column',            v_fk.ref_pk_column,
        'ref_columns',          v_ref_cols,
        'default_label_column', coalesce(v_label_col, v_fk.ref_pk_column)
      )
    )
  );
end;
$fn_bundle$;

revoke all on function public.app_edit_suggestion_schema_bundle() from public;
grant execute on function public.app_edit_suggestion_schema_bundle() to anon, authenticated;

-- --------------------------------------------------------------------------
-- Verification query (run separately after success):
-- --------------------------------------------------------------------------
-- select public.app_edit_suggestion_schema_bundle();

-- --------------------------------------------------------------------------
-- 7d) reports insert hardening (see migration 20260505120000_reports_insert_hardening.sql)
-- --------------------------------------------------------------------------
alter table public.reports
  alter column info_issue_type set default 'other';

alter table public.reports
  alter column suggested_correction set default '';

create or replace function public.app_list_table_columns(
  p_schema text,
  p_table text
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'column_name', q.colname,
        'data_type', q.data_type_fmt,
        'udt_name', q.udt_name,
        'is_nullable', q.is_nullable_yn,
        'is_primary_key', q.is_pk,
        'fk_ref_schema', q.fk_ref_schema,
        'fk_ref_table', q.fk_ref_table,
        'fk_ref_column', q.fk_ref_column,
        'description', q.description
      )
      order by q.attnum
    ),
    '[]'::jsonb
  )
  from (
    select
      a.attname::text as colname,
      pg_catalog.format_type(a.atttypid, a.atttypmod) as data_type_fmt,
      t.typname::text as udt_name,
      case when a.attnotnull then 'NO' else 'YES' end as is_nullable_yn,
      a.attnum,
      exists (
        select 1
        from pg_index i
        where i.indrelid = a.attrelid
          and i.indisprimary
          and a.attnum = any (i.indkey)
      ) as is_pk,
      fk.fk_ref_schema,
      fk.fk_ref_table,
      fk.fk_ref_column,
      pg_catalog.col_description(a.attrelid, a.attnum) as description
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_type t on t.oid = a.atttypid
    left join lateral (
      select
        sch2.nspname::text as fk_ref_schema,
        cl2.relname::text as fk_ref_table,
        a2.attname::text as fk_ref_column
      from pg_constraint con
      join pg_class cl1 on cl1.oid = con.conrelid
      join pg_namespace sch1 on sch1.oid = cl1.relnamespace
      join unnest(con.conkey, con.confkey) as u(src_att, dst_att) on true
      join pg_attribute a1
        on a1.attrelid = con.conrelid
       and a1.attnum = u.src_att
       and a1.attname = a.attname
      join pg_class cl2 on cl2.oid = con.confrelid
      join pg_namespace sch2 on sch2.oid = cl2.relnamespace
      join pg_attribute a2
        on a2.attrelid = con.confrelid
       and a2.attnum = u.dst_att
      where sch1.nspname::text = n.nspname
        and cl1.relname::text = c.relname
        and con.contype = 'f'
      limit 1
    ) fk on true
    where n.nspname = p_schema
      and c.relname = p_table
      and c.relkind in ('r', 'p', 'f')
      and a.attnum > 0
      and not a.attisdropped
  ) q;
$$;

revoke all on function public.app_list_table_columns(text, text) from public;
grant execute on function public.app_list_table_columns(text, text) to anon, authenticated;

create or replace function public.app_edit_suggestion_schema_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $fn_bundle_pref_doctor$
declare
  v_reports_exists boolean;
  v_reports_cols   jsonb;
  v_fk_column      text;
  v_ref_schema     text;
  v_ref_table      text;
  v_ref_pk_column  text;
  v_ref_cols       jsonb;
  v_label_col      text;
begin
  select exists (
    select 1
    from pg_class     c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'reports'
      and c.relkind = 'r'
  ) into v_reports_exists;

  if not coalesce(v_reports_exists, false) then
    return jsonb_build_object(
      'ok', false,
      'error', 'reports table not found in schema public'
    );
  end if;

  v_reports_cols := public.app_list_table_columns('public', 'reports');

  select
    a1.attname::text into v_fk_column
  from pg_constraint  con
  join pg_class       cl1  on cl1.oid  = con.conrelid
  join pg_namespace   nsp1 on nsp1.oid = cl1.relnamespace
  join pg_attribute   a1
    on a1.attrelid = con.conrelid
   and a1.attnum   = con.conkey[1]
   and not a1.attisdropped
  join pg_class       cl2  on cl2.oid  = con.confrelid
  join pg_namespace   nsp2 on nsp2.oid = cl2.relnamespace
  where nsp1.nspname = 'public'
    and cl1.relname  = 'reports'
    and con.contype  = 'f'
  order by
    case
      when nsp2.nspname = 'public'
       and cl2.relname = 'doctors'
       and a1.attname = 'doctor_id'
      then 0
      else 1
    end,
    con.conname
  limit 1;

  if v_fk_column is null then
    if exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'doctors' and c.relkind = 'r'
    ) and exists (
      select 1 from pg_attribute a
      join pg_class cl on cl.oid = a.attrelid
      join pg_namespace n on n.oid = cl.relnamespace
      where n.nspname = 'public' and cl.relname = 'reports'
        and a.attname = 'doctor_id' and not a.attisdropped
    ) then
      v_fk_column     := 'doctor_id';
      v_ref_schema    := 'public';
      v_ref_table     := 'doctors';
      v_ref_pk_column := 'id';
    else
      return jsonb_build_object(
        'ok',      true,
        'reports', jsonb_build_object(
          'schema', 'public', 'table', 'reports', 'columns', v_reports_cols
        ),
        'targets', '[]'::jsonb
      );
    end if;
  else
    select
      nsp2.nspname::text,
      cl2.relname::text,
      a2.attname::text
    into v_ref_schema, v_ref_table, v_ref_pk_column
    from pg_constraint  con
    join pg_class       cl1  on cl1.oid  = con.conrelid
    join pg_namespace   nsp1 on nsp1.oid = cl1.relnamespace
    join pg_attribute   a1
      on a1.attrelid = con.conrelid
     and a1.attnum   = con.conkey[1]
     and a1.attname  = v_fk_column
    join pg_class       cl2  on cl2.oid  = con.confrelid
    join pg_namespace   nsp2 on nsp2.oid = cl2.relnamespace
    join pg_attribute   a2
      on a2.attrelid = con.confrelid
     and a2.attnum   = con.confkey[1]
    where nsp1.nspname = 'public'
      and cl1.relname  = 'reports'
      and con.contype  = 'f'
    order by
      case
        when nsp2.nspname = 'public'
         and cl2.relname = 'doctors'
         and a1.attname = 'doctor_id'
        then 0
        else 1
      end,
      con.conname
    limit 1;
  end if;

  v_ref_cols := public.app_list_table_columns(v_ref_schema, v_ref_table);

  select a.attname::text
  into v_label_col
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_type t on t.oid = a.atttypid
  where n.nspname = v_ref_schema
    and c.relname = v_ref_table
    and a.attnum > 0
    and not a.attisdropped
    and a.attname <> v_ref_pk_column
    and t.typname in ('text', 'varchar', 'bpchar')
  order by case a.attname
    when 'name'  then 0
    when 'title' then 1
    else 2
  end, a.attnum
  limit 1;

  return jsonb_build_object(
    'ok',      true,
    'reports', jsonb_build_object(
      'schema', 'public', 'table', 'reports', 'columns', v_reports_cols
    ),
    'targets', jsonb_build_array(
      jsonb_build_object(
        'fk_column',            v_fk_column,
        'ref_schema',           v_ref_schema,
        'ref_table',            v_ref_table,
        'pk_column',            v_ref_pk_column,
        'ref_columns',          v_ref_cols,
        'default_label_column', coalesce(v_label_col, v_ref_pk_column)
      )
    )
  );
end;
$fn_bundle_pref_doctor$;

revoke all on function public.app_edit_suggestion_schema_bundle() from public;
grant execute on function public.app_edit_suggestion_schema_bundle() to anon, authenticated;
