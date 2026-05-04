-- Harden public.reports inserts: safe defaults for NOT NULL columns, prefer
-- doctor_id -> doctors when multiple FKs exist, list report columns via
-- pg_catalog (information_schema can hide rows in some privilege contexts).

-- --------------------------------------------------------------------------
-- 1) Defaults so omitted keys still satisfy NOT NULL (e.g. introspection drift)
-- --------------------------------------------------------------------------
alter table public.reports
  alter column info_issue_type set default 'other';

alter table public.reports
  alter column suggested_correction set default '';

-- --------------------------------------------------------------------------
-- 2) Column list via pg_catalog (same JSON shape as before for Flutter)
-- --------------------------------------------------------------------------
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

-- --------------------------------------------------------------------------
-- 3) Bundle RPC: prefer FK public.doctors(doctor_id) when multiple FKs exist
-- --------------------------------------------------------------------------
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
