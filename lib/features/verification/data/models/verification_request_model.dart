enum VerificationStatus { pending, approved, rejected }

extension VerificationStatusX on VerificationStatus {
  String get value => name;

  static VerificationStatus fromString(String? s) => switch (s) {
        'approved' => VerificationStatus.approved,
        'rejected' => VerificationStatus.rejected,
        _          => VerificationStatus.pending,
      };
}

class VerificationRequestModel {
  const VerificationRequestModel({
    required this.id,
    required this.doctorId,
    required this.status,
    this.idCardFrontUrl,
    this.idCardBackUrl,
    this.medicalLicenseUrl,
    this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String doctorId;
  final VerificationStatus status;
  final String? idCardFrontUrl;
  final String? idCardBackUrl;
  final String? medicalLicenseUrl;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Supabase may return [doctor_id] as int (bigint) or String after schema migrations.
  static String _idToString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  factory VerificationRequestModel.fromJson(Map<String, dynamic> json) {
    return VerificationRequestModel(
      id:                  json['id'] as String,
      doctorId:            _idToString(json['doctor_id']),
      status:              VerificationStatusX.fromString(json['status'] as String?),
      idCardFrontUrl:      json['id_card_front_url'] as String?,
      idCardBackUrl:       json['id_card_back_url'] as String?,
      medicalLicenseUrl:   json['medical_license_url'] as String?,
      adminNotes:          json['admin_notes'] as String?,
      createdAt:           DateTime.parse(json['created_at'] as String),
      updatedAt:           DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id':                   id,
        'doctor_id':            doctorId,
        'status':               status.value,
        'id_card_front_url':    idCardFrontUrl,
        'id_card_back_url':     idCardBackUrl,
        'medical_license_url':  medicalLicenseUrl,
        'admin_notes':          adminNotes,
        'created_at':           createdAt.toIso8601String(),
        'updated_at':           updatedAt.toIso8601String(),
      };
}
