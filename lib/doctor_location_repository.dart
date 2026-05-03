import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorLocationRepository {
  DoctorLocationRepository._();

  static final DoctorLocationRepository instance =
      DoctorLocationRepository._();

  Future<void> recordLocationConfirmation(
    SupabaseClient supabase,
    int doctorId,
  ) async {
    debugPrint('[LocationRepo] confirm location for doctor $doctorId');
  }

  Future<void> submitLocationCorrection(
    SupabaseClient supabase, {
    required int doctorId,
    required double lat,
    required double lng,
  }) async {
    debugPrint(
      '[LocationRepo] correct location for doctor $doctorId: $lat, $lng',
    );
  }
}
