// ✅ UPDATED 2026-05-09
// Minimal hardcoded schema bundle used when the RPC `app_edit_suggestion_schema_bundle`
// is unavailable (network failure, RLS block on information_schema, etc.).
// Matches the actual Supabase schema as of migration 20260510.
import '../../edit_suggestion/schema_models.dart';

EditSuggestionSchemaBundle buildFallbackBundle() {
  const List<SchemaColumn> reportColumns = <SchemaColumn>[
    SchemaColumn(
      columnName: 'id',
      dataType: 'integer',
      isNullable: false,
      isPrimaryKey: true,
    ),
    SchemaColumn(
      columnName: 'doctor_id',
      dataType: 'integer',
      isNullable: false,
      isPrimaryKey: false,
      fkRefSchema: 'public',
      fkRefTable: 'doctors',
      fkRefColumn: 'id',
    ),
    SchemaColumn(
      columnName: 'info_issue_type',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'error_location',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'suggested_correction',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'status',
      dataType: 'text',
      isNullable: false,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'suggested_latitude',
      dataType: 'double precision',
      udtName: 'float8',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'suggested_longitude',
      dataType: 'double precision',
      udtName: 'float8',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'doctor_name',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'target_type',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'field_name',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'new_value',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'metadata',
      dataType: 'jsonb',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'created_at',
      dataType: 'timestamp with time zone',
      isNullable: true,
      isPrimaryKey: false,
    ),
  ];

  const List<SchemaColumn> doctorColumns = <SchemaColumn>[
    SchemaColumn(
      columnName: 'id',
      dataType: 'integer',
      isNullable: false,
      isPrimaryKey: true,
    ),
    SchemaColumn(
      columnName: 'name',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'spec',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'addr',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'ph',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'ph2',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'notes',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'area',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'gove',
      dataType: 'text',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'latitude',
      dataType: 'double precision',
      udtName: 'float8',
      isNullable: true,
      isPrimaryKey: false,
    ),
    SchemaColumn(
      columnName: 'longitude',
      dataType: 'double precision',
      udtName: 'float8',
      isNullable: true,
      isPrimaryKey: false,
    ),
  ];

  return const EditSuggestionSchemaBundle(
    ok: true,
    reportsSchema: 'public',
    reportsTable: 'reports',
    reportColumns: reportColumns,
    targets: <EditSuggestionTarget>[
      EditSuggestionTarget(
        fkColumn: 'doctor_id',
        refSchema: 'public',
        refTable: 'doctors',
        pkColumn: 'id',
        defaultLabelColumn: 'name',
        refColumns: doctorColumns,
      ),
    ],
  );
}
