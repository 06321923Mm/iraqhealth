class Doctor {
  const Doctor({
    required this.id,
    required this.spec,
    required this.name,
    required this.addr,
    required this.area,
    required this.ph,
    required this.ph2,
    required this.notes,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String spec;
  final String name;
  final String addr;
  final String area;
  final String ph;
  final String ph2;
  final String notes;

  /// From Supabase `latitude` / `longitude` (WGS84 degrees); null if unknown.
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  Doctor withCoordinates(double newLatitude, double newLongitude) {
    return Doctor(
      id: id,
      spec: spec,
      name: name,
      addr: addr,
      area: area,
      ph: ph,
      ph2: ph2,
      notes: notes,
      latitude: newLatitude,
      longitude: newLongitude,
    );
  }

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

  factory Doctor.fromJson(Map<String, dynamic> json) {
    final dynamic rawId = json['id'];
    final int id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    return Doctor(
      id: id,
      spec: (json['spec'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      addr: (json['addr'] ?? '').toString(),
      area: (json['area'] ?? '').toString(),
      ph: (json['ph'] ?? '').toString(),
      ph2: (json['ph2'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      latitude: _readDouble(json['latitude']) ?? _readDouble(json['lat']),
      longitude: _readDouble(json['longitude']) ?? _readDouble(json['lng']),
    );
  }
}
