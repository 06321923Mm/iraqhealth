import 'schema_models.dart';

bool isReporterSkippableColumn(SchemaColumn c) {
  if (c.isPrimaryKey) {
    return true;
  }
  final String n = c.columnName.toLowerCase();
  return n == 'created_at' ||
      n == 'updated_at' ||
      n == 'location_correction_count' ||
      n == 'location_confirmations';
}

/// Numeric columns whose names imply map coordinates.
bool isCoordinateLikeColumn(SchemaColumn c) {
  if (!c.isNumericType) {
    return false;
  }
  final String n = c.columnName.toLowerCase();
  return n.contains('lat') ||
      n.contains('lon') ||
      n.endsWith('lng') ||
      n.contains('coord');
}

bool isMapsLinkOrLocationTextColumn(SchemaColumn c) {
  final String n = c.columnName.toLowerCase();
  if (c.isUuidType) {
    return false;
  }
  return n.contains('map') && (n.contains('url') || n.contains('link'));
}

List<SchemaColumn> reporterSelectableColumns(EditSuggestionTarget? t) {
  if (t == null) {
    return const <SchemaColumn>[];
  }
  final List<SchemaColumn> all = t.refColumns
      .where((SchemaColumn c) => !isReporterSkippableColumn(c))
      .toList(growable: false);
  return _deduplicateCoordPairs(all);
}

/// If both latitude and longitude exist, keep only latitude (shown as one map option).
List<SchemaColumn> _deduplicateCoordPairs(List<SchemaColumn> cols) {
  final Set<String> names =
      cols.map((SchemaColumn c) => c.columnName.toLowerCase()).toSet();
  final bool hasLat = names.contains('latitude') || names.contains('lat');
  if (!hasLat) {
    return cols;
  }
  return cols.where((SchemaColumn c) {
    final String n = c.columnName.toLowerCase();
    return n != 'longitude' && n != 'lng' && n != 'lon';
  }).toList(growable: false);
}
