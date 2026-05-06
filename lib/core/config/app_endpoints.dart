import 'package:flutter/foundation.dart' show kDebugMode;

/// Centralized constants for all Supabase table/bucket names and future API endpoints.
abstract final class AppEndpoints {
  // ── Supabase tables ──────────────────────────────────────────────────────────
  static const String doctors               = 'doctors';
  static const String reports               = 'reports';
  static const String doctorReportTotals    = 'doctor_report_totals';
  static const String pendingDoctors        = 'pending_doctors';
  static const String clinicClaimRequests   = 'clinic_claim_requests';
  static const String verificationRequests  = 'verification_requests';

  // ── Supabase storage buckets ─────────────────────────────────────────────────
  static const String clinicProfileImages   = 'clinic-profile-images';
  static const String verificationDocs      = 'verification-docs';

  // ── Future iraqhealth.net API ────────────────────────────────────────────────
  static const String _prodBase    = 'https://iraqhealth.net';
  static const String _devBase     = 'https://dev.iraqhealth.net';

  static String get apiBaseUrl  => kDebugMode ? '$_devBase/api'    : '$_prodBase/api';
  static String get appBaseUrl  => kDebugMode ? _devBase           : _prodBase;
  static String get adminBaseUrl => kDebugMode ? '$_devBase/admin'  : '$_prodBase/admin';
}
