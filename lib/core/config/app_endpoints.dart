// ✅ UPDATED 2026-05-09
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
  static const String specializations       = 'specializations';
  static const String dailyReportCounts     = 'daily_report_counts';

  // ── Supabase RPC names ───────────────────────────────────────────────────────
  static const String adminApproveVerification     = 'admin_approve_verification';
  static const String adminRejectVerification      = 'admin_reject_verification';
  static const String adminApplyReportCorrection   = 'admin_apply_report_correction';
  static const String adminApplyCoordCorrection    = 'admin_apply_coord_correction';
  static const String suggestSpecialization        = 'suggest_specialization';
  static const String getDoctorsPageKeyset         = 'get_doctors_page_keyset';
  static const String findDuplicateDoctor          = 'find_duplicate_doctor';
  static const String dailyReportQuota             = 'daily_report_quota';
  static const String refreshDoctorReportRatios    = 'refresh_doctor_report_ratios';

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
