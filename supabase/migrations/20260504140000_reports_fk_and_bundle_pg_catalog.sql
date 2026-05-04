-- Ensure reports.doctor_id FK exists; update bundle RPC to use pg_catalog
-- (information_schema FK visibility can be restricted in security-definer context).

-- --------------------------------------------------------------------------
-- 1) Add FK from reports.doctor_id -> doctors.id if it does not exist
-- --------------------------------------------------------------------------
do $add_fk$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class     cl on cl.oid = c.conrelid
    join pg_namespace n  on n.oid  = cl.relnamespace
    where n.nspname  = 'public'
      and cl.relname = 'reports'
      and c.contype  = 'f'
  ) then
    -- Remove orphaned rows so the FK can be created cleanly.
    delete from public.reports r
    where not exists (
      select 1 from public.doctors d where d.id = r.doctor_id
    );

    alter table public.reports
      add constraint reports_doctor_id_fkey
      foreign key (doctor_id) references public.doctors(id) on delete cascade;
  end if;
end $add_fk$;

-- --------------------------------------------------------------------------
-- 2) Rebuild bundle RPC using pg_catalog for FK detection
-- --------------------------------------------------------------------------
create or replace function public.app_edit_suggestion_schema_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn_bundle2$
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

  -- Use pg_catalog directly (bypasses information_schema privilege filter).
  select
    a1.attname::text   into v_fk_column
  from pg_constraint  con
  join pg_class       cl1  on cl1.oid  = con.conrelid
  join pg_namespace   nsp1 on nsp1.oid = cl1.relnamespace
  join pg_attribute   a1
    on a1.attrelid = con.conrelid
   and a1.attnum   = con.conkey[1]
   and not a1.attisdropped
  where nsp1.nspname = 'public'
    and cl1.relname  = 'reports'
    and con.contype  = 'f'
  order by con.conname
  limit 1;

  if v_fk_column is null then
    -- Fallback: if no FK found but doctor_id column and doctors table exist,
    -- treat it as the implicit FK target.
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
    -- Resolve the referenced table from pg_catalog.
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
    order by con.conname
    limit 1;
  end if;

  v_ref_cols := public.app_list_table_columns(v_ref_schema, v_ref_table);

  select c.column_name
  into v_label_col
  from information_schema.columns c
  where c.table_schema = v_ref_schema
    and c.table_name   = v_ref_table
    and c.column_name <> v_ref_pk_column
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
$fn_bundle2$;

revoke all on function public.app_edit_suggestion_schema_bundle() from public;
grant execute on function public.app_edit_suggestion_schema_bundle() to anon, authenticated;
