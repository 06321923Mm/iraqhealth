import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists doctor map coordinates and location feedback in Supabase only.
class DoctorLocationRepository {
  DoctorLocationRepository._();
  static final DoctorLocationRepository instance = DoctorLocationRepository._();

  Future<void> recordLocationConfirmation(
    SupabaseClient client,
    int doctorId,
  ) async {
    if (kIsWeb || doctorId <= 0) {
      return;
    }
    try {
      await client.rpc(
        'increment_doctor_location_confirmations',
        params: <String, dynamic>{'p_doctor_id': doctorId},
      );
    } catch (e, st) {
      debugPrint('[DoctorLocationRepository] recordLocationConfirmation: $e $st');
      rethrow;
    }
  }

  Future<void> submitLocationCorrection(
    SupabaseClient client, {
    required int doctorId,
    required double latitude,
    required double longitude,
  }) async {
    if (kIsWeb || doctorId <= 0) {
      return;
    }
    try {
      await client.rpc(
        'submit_doctor_location_coordinates',
        params: <String, dynamic>{
          'p_doctor_id': doctorId,
          'p_lat': latitude,
          'p_lng': longitude,
        },
      );
    } catch (e, st) {
      debugPrint('[DoctorLocationRepository] submitLocationCorrection: $e $st');
      rethrow;
    }
  }
}
