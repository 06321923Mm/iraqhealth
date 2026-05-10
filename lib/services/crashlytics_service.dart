// خدمة Crashlytics المركزية — كل الأخطاء تمر من هنا
// الخصوصية: لا نُخزّن أي بيانات شخصية مباشرة

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  static final CrashlyticsService instance = CrashlyticsService._();
  CrashlyticsService._();

  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  // PRIVACY: userId is one-way hashed — original value is never stored or sent.
  void setUser(String? userId, {String? role, String? governorate}) {
    try {
      if (userId == null) return;
      final String maskedId = userId.hashCode.toRadixString(16);
      _c.setUserIdentifier(maskedId);
      setCustomKey('user_role', role ?? 'guest');
      setCustomKey('governorate', governorate ?? 'unknown');
    } catch (e) {
      debugPrint('CrashlyticsService.setUser error: $e');
    }
  }

  void setCustomKey(String key, Object value) {
    try {
      _c.setCustomKey(key, value);
    } catch (e) {
      debugPrint('CrashlyticsService.setCustomKey($key) error: $e');
    }
  }

  void setScreen(String screenName) {
    try {
      setCustomKey('current_screen', screenName);
      _c.log('screen: $screenName');
    } catch (e) {
      debugPrint('CrashlyticsService.setScreen error: $e');
    }
  }

  void setNetworkState(bool isOnline) {
    try {
      setCustomKey('network_state', isOnline ? 'online' : 'offline');
    } catch (e) {
      debugPrint('CrashlyticsService.setNetworkState error: $e');
    }
  }

  void setAppContext({required String version, required String build}) {
    try {
      setCustomKey('app_version', version);
      setCustomKey('build_number', build);
    } catch (e) {
      debugPrint('CrashlyticsService.setAppContext error: $e');
    }
  }

  void logError(
    dynamic error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    try {
      if (kDebugMode) {
        debugPrint('CrashlyticsService.logError: $error\n$stack');
      }
      if (reason != null) _c.log('reason: $reason');
      _c.recordError(error, stack, fatal: fatal);
    } catch (e) {
      debugPrint('CrashlyticsService.logError failed: $e');
    }
  }

  void logApiFailure(String endpoint, dynamic error, StackTrace stack) {
    try {
      _c.log('api_failure: $endpoint');
      setCustomKey('last_failed_endpoint', endpoint);
      logError(error, stack, reason: 'api_failure:$endpoint');
    } catch (e) {
      debugPrint('CrashlyticsService.logApiFailure error: $e');
    }
  }

  // PRIVACY: provider name only (e.g. 'supabase', 'google') — no credentials logged.
  void logAuthFailure(String provider, dynamic error) {
    try {
      _c.log('auth_failure: $provider');
      setCustomKey('last_auth_provider', provider);
      logError(error, null, reason: 'auth_failure:$provider');
    } catch (e) {
      debugPrint('CrashlyticsService.logAuthFailure error: $e');
    }
  }
}
