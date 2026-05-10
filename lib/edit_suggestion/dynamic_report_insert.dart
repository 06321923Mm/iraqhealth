import 'column_edit_semantics.dart';
import 'schema_models.dart';

/// Builds an INSERT map for [bundle.reportsTable] using only keys that exist
/// on the live `reports` table (from introspection). Omits null values for
/// optional columns so PostgREST accepts the row.
class DynamicReportInsertBuilder {
  DynamicReportInsertBuilder(this.bundle);

  final EditSuggestionSchemaBundle bundle;

  Set<String> get _cols => bundle.reportColumnNames;

  bool _has(String name) => _cols.contains(name);

  /// [targetPkValue] — typed id (int, String for uuid, etc.)
  Map<String, dynamic> build({
    required Object targetPkValue,
    required String doctorNameSnapshot,
    required SchemaColumn selectedField,
    required String suggestedText,
    required String statusPendingValue,
    double? suggestedLatitude,
    double? suggestedLongitude,
    Map<String, dynamic>? metadataExtra,
  }) {
    final EditSuggestionTarget? t = bundle.primaryTarget;
    if (t == null) {
      return <String, dynamic>{};
    }
    final String fkCol = t.fkColumn;
    final Map<String, dynamic> row = <String, dynamic>{};

    void putIfHas(String col, dynamic value) {
      if (_has(col) && value != null) {
        row[col] = value;
      }
    }

    putIfHas(fkCol, targetPkValue);

    final bool loc = isCoordinateLikeColumn(selectedField) ||
        isMapsLinkOrLocationTextColumn(selectedField);
    final String issueType = loc ? 'wrong_map_location' : 'field_edit:${selectedField.columnName}';

    final String correctionText = suggestedText.trim().isNotEmpty
        ? suggestedText.trim()
        : (loc &&
                suggestedLatitude != null &&
                suggestedLongitude != null
            ? '${suggestedLatitude.toStringAsFixed(6)}, ${suggestedLongitude.toStringAsFixed(6)}'
            : suggestedText.trim());

    putIfHas('doctor_name', doctorNameSnapshot);
    putIfHas('info_issue_type', issueType);
    putIfHas('error_location', 'غير محدد');
    putIfHas('suggested_correction', correctionText);
    putIfHas('status', statusPendingValue);

    if (loc) {
      putIfHas('suggested_latitude', suggestedLatitude);
      putIfHas('suggested_longitude', suggestedLongitude);
    }

    putIfHas('field_name', selectedField.columnName);
    putIfHas('target_type', t.refTable);

    if (_has('new_value')) {
      final Map<String, dynamic> nv = <String, dynamic>{
        'text': correctionText,
        'column': selectedField.columnName,
      };
      if (suggestedLatitude != null) {
        nv['latitude'] = suggestedLatitude;
      }
      if (suggestedLongitude != null) {
        nv['longitude'] = suggestedLongitude;
      }
      row['new_value'] = nv;
    }

    if (_has('metadata')) {
      final Map<String, dynamic> meta = <String, dynamic>{
        'field_data_type': selectedField.dataType,
        if (metadataExtra != null) ...metadataExtra,
      };
      row['metadata'] = meta;
    }

    return row;
  }
}

/// Reads `field_name` or `field_edit:` prefix from legacy/new rows.
String? resolveReportTargetColumn(Map<String, dynamic> r) {
  final String? fn = r['field_name']?.toString().trim();
  if (fn != null && fn.isNotEmpty) {
    return fn;
  }
  final String? it = r['info_issue_type']?.toString();
  if (it != null && it.startsWith('field_edit:')) {
    return it.substring('field_edit:'.length).trim();
  }
  return null;
}
