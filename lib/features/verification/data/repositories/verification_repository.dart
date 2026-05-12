// ✅ UPDATED 2026-05-09
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../core/services/base_service.dart';
import '../models/verification_request_model.dart';

class VerificationRepository extends BaseService {
  const VerificationRepository(super.db);

  /// Uploads a document file and returns its private storage URL.
  Future<String> uploadDocument({
    required Uint8List bytes,
    required String bucketPath,
    required String contentType,
  }) async {
    await guard(
      () => db.storage.from(AppEndpoints.verificationDocs).uploadBinary(
            bucketPath,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          ),
      context: 'uploadDocument',
    );
    // Return the path; signed URLs are generated on demand for private buckets.
    return bucketPath;
  }

  /// Generates a short-lived signed URL for a private verification doc.
  Future<String> getSignedUrl(String path, {int expiresInSeconds = 3600}) async {
    return guard(
      () => db.storage
          .from(AppEndpoints.verificationDocs)
          .createSignedUrl(path, expiresInSeconds),
      context: 'getSignedUrl',
    ).then((String? url) => url ?? '');
  }

  /// Submits a verification request for [doctorId] with the uploaded document paths.
  Future<bool> submitVerificationRequest({
    required int doctorId,
    required String idCardFrontPath,
    required String idCardBackPath,
    required String medicalLicensePath,
  }) async {
    final String? ownerUid = db.auth.currentUser?.id;
    await guard(
      () => db.from(AppEndpoints.verificationRequests).insert(<String, dynamic>{
            'doctor_id':             doctorId,
            'id_card_front_url':     idCardFrontPath,
            'id_card_back_url':      idCardBackPath,
            'medical_license_url':   medicalLicensePath,
            // Legacy uuid column from doctor_id→bigint migration; DB may still require NOT NULL.
            'doctor_user_id_legacy': ownerUid,
          }),
      context: 'submitVerificationRequest',
    );
    return true;
  }

  Future<int?> fetchDoctorIdForCurrentUser() async {
    final String? uid = db.auth.currentUser?.id;
    if (uid == null) {
      return null;
    }
    final List<dynamic> rows = await db
        .from(AppEndpoints.doctors)
        .select('id')
        .eq('owner_user_id', uid)
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }
    final dynamic id = (rows.first as Map<String, dynamic>)['id'];
    if (id == null) return null;
    if (id is int) return id;
    if (id is num) return id.toInt();
    if (id is String) return int.tryParse(id);
    return null;
  }

  /// Streams the most recent verification request for [doctorId].
  Stream<VerificationRequestModel?> getMyVerificationStatus(String doctorId) {
    return db
        .from(AppEndpoints.verificationRequests)
        .stream(primaryKey: <String>['id'])
        .eq('doctor_id', doctorId)
        .order('created_at', ascending: false)
        .limit(1)
        .map((List<Map<String, dynamic>> rows) =>
            rows.isEmpty ? null : VerificationRequestModel.fromJson(rows.first));
  }
}
