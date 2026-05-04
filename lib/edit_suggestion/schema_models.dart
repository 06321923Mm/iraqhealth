class SchemaColumn {
  const SchemaColumn({
    required this.columnName,
    required this.dataType,
    this.udtName,
    required this.isNullable,
    required this.isPrimaryKey,
    this.fkRefSchema,
    this.fkRefTable,
    this.fkRefColumn,
    this.description,
  });

  final String columnName;
  final String dataType;
  final String? udtName;
  final bool isNullable;
  final bool isPrimaryKey;
  final String? fkRefSchema;
  final String? fkRefTable;
  final String? fkRefColumn;
  final String? description;

  bool get isUuidType {
    final String u = (udtName ?? '').toLowerCase();
    return u == 'uuid' || dataType.toLowerCase() == 'uuid';
  }

  bool get isNumericType {
    final String d = dataType.toLowerCase();
    final String u = (udtName ?? '').toLowerCase();
    return d.contains('numeric') ||
        d.contains('double') ||
        d.contains('real') ||
        u == 'float4' ||
        u == 'float8' ||
        u == 'numeric' ||
        u == 'int2' ||
        u == 'int4' ||
        u == 'int8';
  }

  static SchemaColumn? tryParse(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final String? name = raw['column_name']?.toString();
    if (name == null || name.isEmpty) {
      return null;
    }
    return SchemaColumn(
      columnName: name,
      dataType: (raw['data_type'] ?? '').toString(),
      udtName: raw['udt_name']?.toString(),
      isNullable: (raw['is_nullable']?.toString().toUpperCase() ?? 'YES') == 'YES',
      isPrimaryKey: raw['is_primary_key'] == true,
      fkRefSchema: raw['fk_ref_schema']?.toString(),
      fkRefTable: raw['fk_ref_table']?.toString(),
      fkRefColumn: raw['fk_ref_column']?.toString(),
      description: raw['description']?.toString(),
    );
  }
}

class EditSuggestionTarget {
  const EditSuggestionTarget({
    required this.fkColumn,
    required this.refSchema,
    required this.refTable,
    required this.pkColumn,
    required this.refColumns,
    required this.defaultLabelColumn,
  });

  final String fkColumn;
  final String refSchema;
  final String refTable;
  final String pkColumn;
  final List<SchemaColumn> refColumns;
  final String defaultLabelColumn;

  static EditSuggestionTarget? tryParse(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final List<dynamic>? cols = raw['ref_columns'] as List<dynamic>?;
    return EditSuggestionTarget(
      fkColumn: (raw['fk_column'] ?? '').toString(),
      refSchema: (raw['ref_schema'] ?? 'public').toString(),
      refTable: (raw['ref_table'] ?? '').toString(),
      pkColumn: (raw['pk_column'] ?? '').toString(),
      refColumns: cols == null
          ? const <SchemaColumn>[]
          : cols
              .map(SchemaColumn.tryParse)
              .whereType<SchemaColumn>()
              .toList(growable: false),
      defaultLabelColumn: (raw['default_label_column'] ?? '').toString(),
    );
  }
}

class EditSuggestionSchemaBundle {
  const EditSuggestionSchemaBundle({
    required this.ok,
    this.error,
    required this.reportsSchema,
    required this.reportsTable,
    required this.reportColumns,
    required this.targets,
  });

  final bool ok;
  final String? error;
  final String reportsSchema;
  final String reportsTable;
  final List<SchemaColumn> reportColumns;
  final List<EditSuggestionTarget> targets;

  Set<String> get reportColumnNames =>
      reportColumns.map((SchemaColumn c) => c.columnName).toSet();

  EditSuggestionTarget? get primaryTarget =>
      targets.isEmpty ? null : targets.first;

  static EditSuggestionSchemaBundle parse(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const EditSuggestionSchemaBundle(
        ok: false,
        error: 'invalid bundle',
        reportsSchema: 'public',
        reportsTable: 'reports',
        reportColumns: <SchemaColumn>[],
        targets: <EditSuggestionTarget>[],
      );
    }
    final bool ok = raw['ok'] == true;
    if (!ok) {
      return EditSuggestionSchemaBundle(
        ok: false,
        error: raw['error']?.toString() ?? 'unknown',
        reportsSchema: 'public',
        reportsTable: 'reports',
        reportColumns: const <SchemaColumn>[],
        targets: const <EditSuggestionTarget>[],
      );
    }
    final Map<String, dynamic>? rep =
        raw['reports'] as Map<String, dynamic>?;
    final List<dynamic>? repCols = rep?['columns'] as List<dynamic>?;
    final List<dynamic>? tRaw = raw['targets'] as List<dynamic>?;
    return EditSuggestionSchemaBundle(
      ok: true,
      reportsSchema: (rep?['schema'] ?? 'public').toString(),
      reportsTable: (rep?['table'] ?? 'reports').toString(),
      reportColumns: repCols == null
          ? const <SchemaColumn>[]
          : repCols
              .map(SchemaColumn.tryParse)
              .whereType<SchemaColumn>()
              .toList(growable: false),
      targets: tRaw == null
          ? const <EditSuggestionTarget>[]
          : tRaw
              .map(EditSuggestionTarget.tryParse)
              .whereType<EditSuggestionTarget>()
              .toList(growable: false),
    );
  }
}
