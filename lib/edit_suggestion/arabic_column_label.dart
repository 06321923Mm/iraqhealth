import 'schema_models.dart';

/// Arabic label for a column: prefers Postgres COMMENT from introspection,
/// then common English column-name patterns (not tied to a specific table).
String arabicLabelForColumn(SchemaColumn c) {
  final String? d = c.description?.trim();
  if (d != null && d.isNotEmpty) {
    return d;
  }
  return _fallbackArabicLabel(c.columnName);
}

String _fallbackArabicLabel(String columnName) {
  final String n = columnName.toLowerCase().trim();
  const Map<String, String> exact = <String, String>{
    'id': 'المعرّف',
    'name': 'الاسم',
    'spec': 'التخصص',
    'addr': 'العنوان',
    'address': 'العنوان',
    'area': 'المنطقة',
    'ph': 'الرقم',
    'ph2': 'الرقم الثاني',
    'phone': 'الرقم',
    'mobile': 'الرقم',
    'notes': 'الملاحظات',
    'latitude': 'الموقع على الخريطة',
    'longitude': 'الموقع على الخريطة',
    'lat': 'الموقع على الخريطة',
    'lng': 'الموقع على الخريطة',
    'lon': 'الموقع على الخريطة',
    'gove': 'المحافظة',
    'map_url': 'الموقع على خرائط كوكل',
    'map_link': 'الموقع على خرائط كوكل',
  };
  if (exact.containsKey(n)) {
    return exact[n]!;
  }
  if (n.contains('phone') || n.contains('tel') || n.contains('mobile')) {
    return 'الرقم';
  }
  if (n.contains('map') || n.contains('geo')) {
    return 'الموقع على خرائط كوكل';
  }
  if (n.contains('addr') || n.contains('address')) {
    return 'العنوان';
  }
  if (n.contains('lat') || n.contains('lon') || n.endsWith('lng')) {
    return 'الموقع على الخريطة';
  }
  return columnName;
}
