import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics only: six custom events (no business data storage).
///
/// On web, Firebase is not initialized in this app; all methods no-op safely.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static const int _maxParamNameLen = 40;
  static const int _maxStringValueLen = 100;

  FirebaseAnalytics? get _analytics => kIsWeb ? null : FirebaseAnalytics.instance;

  void _debugPrintEvent(String name, Map<String, Object?> params) {
    if (kDebugMode) {
      debugPrint('[Analytics] $name params=$params');
    }
  }

  Map<String, Object> _sanitizeParams(Map<String, Object?> raw) {
    final Map<String, Object> out = <String, Object>{};
    for (final MapEntry<String, Object?> e in raw.entries) {
      if (e.value == null) {
        continue;
      }
      String key = e.key;
      if (key.length > _maxParamNameLen) {
        key = key.substring(0, _maxParamNameLen);
      }
      final Object v = e.value!;
      if (v is String) {
        final String s = v.trim();
        out[key] = s.length > _maxStringValueLen
            ? s.substring(0, _maxStringValueLen)
            : s;
      } else {
        out[key] = v;
      }
    }
    return out;
  }

  Future<void> _logEvent(String name, Map<String, Object?> params) async {
    _debugPrintEvent(name, params);
    final FirebaseAnalytics? a = _analytics;
    if (a == null) {
      return;
    }
    try {
      await a.logEvent(name: name, parameters: _sanitizeParams(params));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Analytics] logEvent failed: $e');
      }
    }
  }

  Future<void> logDoctorOpened(String doctorName, String specialty) {
    return _logEvent('doctor_opened', <String, Object?>{
      'doctor_name': doctorName,
      'specialty': specialty,
    });
  }

  Future<void> logCallClicked(String doctorName) {
    return _logEvent('call_clicked', <String, Object?>{
      'doctor_name': doctorName,
    });
  }

  Future<void> logWhatsappClicked(String doctorName) {
    return _logEvent('whatsapp_clicked', <String, Object?>{
      'doctor_name': doctorName,
    });
  }

  Future<void> logSearchUsed(String query) {
    return _logEvent('search_used', <String, Object?>{
      'query': query,
    });
  }

  Future<void> logFilterUsed(String filterType, {String value = ''}) {
    return _logEvent('filter_used', <String, Object?>{
      'filter_type': filterType,
      if (value.isNotEmpty) 'value': value,
    });
  }

  /// [kind] e.g. `coordinates` | `address_text`
  Future<void> logLocationUsed(String kind, {String detail = ''}) {
    return _logEvent('location_used', <String, Object?>{
      'kind': kind,
      if (detail.isNotEmpty) 'detail': detail,
    });
  }

  /// Logs how long (milliseconds) it took to show the first doctor card.
  Future<void> logLoadTime(String governorate, int ms, {bool cacheHit = false}) {
    return _logEvent('load_time', <String, Object?>{
      'governorate': governorate,
      'ms': ms,
      'cache_hit': cacheHit ? 1 : 0,
    });
  }

  /// Logs a governorate switch — helps understand which gove gets the most traffic.
  Future<void> logGovernorateSelected(String governorate) {
    return _logEvent('governorate_selected', <String, Object?>{
      'governorate': governorate,
    });
  }
}
