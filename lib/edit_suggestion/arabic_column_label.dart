import 'schema_models.dart';

bool _descriptionLooksArabic(String d) {
  return RegExp(r'[\u0600-\u06FF]').hasMatch(d);
}

/// Arabic label for a column: prefers Postgres COMMENT only when it contains
/// Arabic (English-only COMMENTs from migrations are ignored), then a fixed map
/// and name heuristics — never the raw English column name for end users.
String arabicLabelForColumn(SchemaColumn c) {
  final String? d = c.description?.trim();
  if (d != null && d.isNotEmpty && _descriptionLooksArabic(d)) {
    return d;
  }
  return _fallbackArabicLabel(c.columnName);
}

String _fallbackArabicLabel(String columnName) {
  final String n = columnName.toLowerCase().trim();
  const Map<String, String> exact = <String, String>{
    'id': 'المعرّف',
    'doctor_id': 'رقم العيادة المرتبطة',
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
    'map_url': 'رابط الخرائط',
    'map_link': 'رابط الخرائط',
    'owner_user_id': 'معرّف حساب المالك',
    'is_verified': 'حالة التوثيق',
    'current_status': 'حالة التوفر',
    'status_message': 'رسالة الحالة',
    'status_expires_at': 'انتهاء رسالة الحالة',
    'profile_image_url': 'صورة البروفايل',
    'search_document': 'فهرس البحث (تلقائي)',
    'info_issue_type': 'نوع المشكلة',
    'error_location': 'أين يظهر الخطأ',
    'suggested_correction': 'التصحيح المقترح',
    'doctor_name': 'اسم الطبيب عند الإرسال',
  };
  if (exact.containsKey(n)) {
    return exact[n]!;
  }
  if (n.contains('phone') || n.contains('tel') || n.contains('mobile')) {
    return 'الرقم';
  }
  if (n.contains('map') || n.contains('geo')) {
    return 'رابط الخرائط';
  }
  if (n.contains('addr') || n.contains('address')) {
    return 'العنوان';
  }
  if (n.contains('lat') || n.contains('lon') || n.endsWith('lng')) {
    return 'الموقع على الخريطة';
  }
  if (n.contains('verified')) {
    return 'حالة التوثيق';
  }
  if (n.contains('status')) {
    return 'الحالة';
  }
  if (n.contains('owner') && n.contains('user')) {
    return 'حساب المالك';
  }
  if (n.endsWith('_url') || n.endsWith('_link')) {
    return 'رابط مرتبط';
  }
  return 'حقل من بطاقة العيادة';
}
