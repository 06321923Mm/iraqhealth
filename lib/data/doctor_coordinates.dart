/// Reads and writes doctor map coordinates for Supabase (`latitude` / `longitude`).
abstract final class DoctorCoordinates {
  DoctorCoordinates._();

  static double? _readDouble(dynamic v) {
    if (v == null) {
      return null;
    }
    if (v is num) {
      return v.toDouble();
    }
    if (v is String) {
      return double.tryParse(v.trim());
    }
    return null;
  }

  static double? readLatitude(Map<String, dynamic>? row) {
    if (row == null) {
      return null;
    }
    for (final String k in const <String>['latitude', 'lat']) {
      final double? v = _readDouble(row[k]);
      if (v != null) {
        return v;
      }
    }
    return null;
  }

  static double? readLongitude(Map<String, dynamic>? row) {
    if (row == null) {
      return null;
    }
    for (final String k in const <String>['longitude', 'lng']) {
      final double? v = _readDouble(row[k]);
      if (v != null) {
        return v;
      }
    }
    return null;
  }

  static double? readSuggestedLatitude(Map<String, dynamic>? row) {
    return row == null ? null : _readDouble(row['suggested_latitude']);
  }

  static double? readSuggestedLongitude(Map<String, dynamic>? row) {
    return row == null ? null : _readDouble(row['suggested_longitude']);
  }

  /// Keys for Supabase [doctors] / [pending_doctors] payloads.
  static Map<String, dynamic> supabasePair({
    required double? latitude,
    required double? longitude,
  }) {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
