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
    required this.gove,
    this.lat,
    this.lng,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: (json['id'] as num?)?.toInt() ?? 0,
      spec: json['spec'] as String? ?? '',
      name: json['name'] as String? ?? '',
      addr: json['addr'] as String? ?? '',
      area: json['area'] as String? ?? '',
      ph: json['ph'] as String? ?? '',
      ph2: json['ph2'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      gove: json['gove'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }

  final int id;
  final String spec;
  final String name;
  final String addr;
  final String area;
  final String ph;
  final String ph2;
  final String notes;
  final String gove;
  final double? lat;
  final double? lng;

  bool get hasCoordinates => lat != null && lng != null;

  Doctor withLatLng(double latitude, double longitude) {
    return Doctor(
      id: id,
      spec: spec,
      name: name,
      addr: addr,
      area: area,
      ph: ph,
      ph2: ph2,
      notes: notes,
      gove: gove,
      lat: latitude,
      lng: longitude,
    );
  }
}
