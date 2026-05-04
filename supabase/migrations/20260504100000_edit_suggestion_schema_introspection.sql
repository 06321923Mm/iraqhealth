-- Runtime schema for «اقتراح تعديل»: RPCs read catalogs; optional report columns for generic payloads.

-- ---------------------------------------------------------------------------
-- Optional generic columns on public.reports (backward compatible)
-- ---------------------------------------------------------------------------
alter table public.reports add column if not exists target_type text;
alter table public.reports add column if not exists field_name text;
alter table public.reports add column if not exists new_value jsonb;
alter table public.reports add column if not exists metadata jsonb;

comment on column public.reports.target_type is
  'Logical entity type for the report row (often matches referenced table name).';
comment on column public.reports.field_name is
  'Target column on the referenced entity that the reporter intends to correct.';
comment on column public.reports.new_value is
  'Structured proposed value (text, uuid, or nested coordinates).';
comment on column public.reports.metadata is
  'Optional JSON for client extensions.';

-- ---------------------------------------------------------------------------
-- Column list: name, data type, nullable, primary key, FK target, description
-- ---------------------------------------------------------------------------
create or replace function public.app_list_table_columns(
  p_schema text,
  p_table text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'column_name', c.column_name,
        'data_type', c.data_type,
        'udt_name', c.udt_name,
        'is_nullable', c.is_nullable,
        'is_primary_key', (pk.column_name is not null),
        'fk_ref_schema', fk.fk_ref_schema,
        'fk_ref_table', fk.fk_ref_table,
        'fk_ref_column', fk.fk_ref_column,
        'description', dsc.description
      )
      order by c.ordinal_position
    ),
    '[]'::jsonb
  )
  from information_schema.columns c
  left join lateral (
    select pg_catalog.col_description(a.attrelid, a.attnum) as description
    from pg_attribute a
    join pg_class cl on cl.oid = a.attrelid
    join pg_namespace n on n.oid = cl.relnamespace
    where n.nspname = c.table_schema
      and cl.relname = c.table_name
      and a.attname = c.column_name
      and a.attnum > 0
      and not a.attisdropped
    limit 1
  ) dsc on true
  left join lateral (
    select kcu.column_name
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_schema = kcu.constraint_schema
     and tc.constraint_name = kcu.constraint_name
    where tc.table_schema = c.table_schema
      and tc.table_name = c.table_name
      and tc.constraint_type = 'PRIMARY KEY'
      and kcu.column_name = c.column_name
    limit 1
  ) pk on true
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
     and a1.attname = c.column_name
    join pg_class cl2 on cl2.oid = con.confrelid
    join pg_namespace sch2 on sch2.oid = cl2.relnamespace
    join pg_attribute a2
      on a2.attrelid = con.confrelid
     and a2.attnum = u.dst_att
    where sch1.nspname::text = c.table_schema
      and cl1.relname::text = c.table_name
      and con.contype = 'f'
    limit 1
  ) fk on true
  where c.table_schema = p_schema
    and c.table_name = p_table;
$$;

revoke all on function public.app_list_table_columns(text, text) from public;
grant execute on function public.app_list_table_columns(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- FK options for a referenced table (validated against FKs from public.reports)
-- ---------------------------------------------------------------------------
create or replace function public.app_fk_label_options(
  p_ref_schema text,
  p_ref_table text,
  p_pk_column text,
  p_label_column text,
  p_search text,
  p_limit integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ok boolean;
  v_sql text;
  v_out jsonb;
  v_lim integer := greatest(1, least(coalesce(p_limit, 40), 200));
begin
  select exists (
    select 1
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on tc.constraint_name = kcu.constraint_name
     and tc.table_schema = kcu.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
     and ccu.table_schema = tc.table_schema
    where tc.table_schema = 'public'
      and tc.table_name = 'reports'
      and tc.constraint_type = 'FOREIGN KEY'
      and ccu.table_schema = p_ref_schema
      and ccu.table_name = p_ref_table
      and ccu.column_name = p_pk_column
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
     and c1.table_name = c2.table_name
    where c1.table_schema = p_ref_schema
      and c1.table_name = p_ref_table
      and c1.column_name = p_pk_column
      and c2.column_name = p_label_column
  ) then
    return '[]'::jsonb;
  end if;

  v_sql := format(
    'select coalesce(jsonb_agg(jsonb_build_object(''id'', q.pk::text, ''label'', q.lb)), ''[]''::jsonb)
     from (
       select %I as pk, %I::text as lb
       from %I.%I
       where ($1 = '''' or %I::text ilike ''%%'' || $1 || ''%%'')
       order by lb
       limit %s
     ) q',
    p_pk_column,
    p_label_column,
    p_ref_schema,
    p_ref_table,
    p_label_column,
    v_lim
  );

  execute v_sql into v_out using coalesce(p_search, '');
  return coalesce(v_out, '[]'::jsonb);
end;
$$;

revoke all on function public.app_fk_label_options(text, text, text, text, text, integer) from public;
grant execute on function public.app_fk_label_options(text, text, text, text, text, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Single bundle for clients: reports shape + primary FK target + columns
-- ---------------------------------------------------------------------------
create or replace function public.app_edit_suggestion_schema_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_reports_exists boolean;
  v_reports_cols jsonb;
  v_fk record;
  v_ref_cols jsonb;
  v_label_col text;
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
      'ok', false,
      'error', 'reports table not found in schema public'
    );
  end if;

  v_reports_cols := public.app_list_table_columns('public', 'reports');

  select
    kcu.column_name as fk_column,
    ccu.table_schema as ref_schema,
    ccu.table_name as ref_table,
    ccu.column_name as ref_pk_column
  into v_fk
  from information_schema.table_constraints tc
  join information_schema.key_column_usage kcu
    on tc.constraint_name = kcu.constraint_name
   and tc.table_schema = kcu.table_schema
  join information_schema.constraint_column_usage ccu
    on ccu.constraint_name = tc.constraint_name
   and ccu.table_schema = tc.table_schema
  where tc.table_schema = 'public'
    and tc.table_name = 'reports'
    and tc.constraint_type = 'FOREIGN KEY'
  order by tc.constraint_name, kcu.ordinal_position
  limit 1;

  if v_fk is null then
    return jsonb_build_object(
      'ok', true,
      'reports', jsonb_build_object(
        'schema', 'public',
        'table', 'reports',
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
    and c.table_name = v_fk.ref_table
    and c.column_name <> v_fk.ref_pk_column
    and c.data_type in ('text', 'character varying')
  order by case c.column_name
    when 'name' then 0
    when 'title' then 1
    else 2
  end,
  c.ordinal_position
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'reports', jsonb_build_object(
      'schema', 'public',
      'table', 'reports',
      'columns', v_reports_cols
    ),
    'targets', jsonb_build_array(
      jsonb_build_object(
        'fk_column', v_fk.fk_column,
        'ref_schema', v_fk.ref_schema,
        'ref_table', v_fk.ref_table,
        'pk_column', v_fk.ref_pk_column,
        'ref_columns', v_ref_cols,
        'default_label_column', coalesce(v_label_col, v_fk.ref_pk_column)
      )
    )
  );
end;
$$;

revoke all on function public.app_edit_suggestion_schema_bundle() from public;
grant execute on function public.app_edit_suggestion_schema_bundle() to anon, authenticated;
