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
    this.profileImageUrl,
    this.imageBlurhash,
    this.isVerified = false,
    this.verificationDate,
    this.lastStatusUpdate,
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

  /// Optional remote URL to the clinic profile image.
  final String? profileImageUrl;

  /// BlurHash placeholder paired with [profileImageUrl] for instant preview.
  final String? imageBlurhash;

  /// Trust layer: verified clinic flag + timestamps.
  final bool isVerified;
  final DateTime? verificationDate;
  final DateTime? lastStatusUpdate;

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
      profileImageUrl: profileImageUrl,
      imageBlurhash: imageBlurhash,
      isVerified: isVerified,
      verificationDate: verificationDate,
      lastStatusUpdate: lastStatusUpdate,
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

  static DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory Doctor.fromJson(Map<String, dynamic> json) {
    final dynamic rawId = json['id'];
    final int id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final String? imageUrl = (json['profile_image_url'] ??
            json['image_url'] ??
            json['photo_url'])
        ?.toString();
    final String? hash = json['image_blurhash']?.toString();
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
      profileImageUrl: (imageUrl == null || imageUrl.trim().isEmpty)
          ? null
          : imageUrl.trim(),
      imageBlurhash: (hash == null || hash.trim().isEmpty) ? null : hash.trim(),
      isVerified: json['is_verified'] == true,
      verificationDate: _readDate(json['verification_date']),
      lastStatusUpdate: _readDate(json['last_status_update']),
    );
  }
}
