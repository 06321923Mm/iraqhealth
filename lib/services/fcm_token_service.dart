import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Retrieves the FCM device token and persists it in `public.user_fcm_tokens`.
/// Call [register] once after the user is authenticated (e.g., on home screen init).
class FcmTokenService {
  FcmTokenService._();

  static Future<void> register() async {
    // FCM is only available on native + web platforms where Firebase is initialized.
    final String? uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      String? token;
      if (kIsWeb) {
        // Web requires a VAPID key — skip silently if not configured.
        return;
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }

      if (token == null || token.isEmpty) return;

      final String platform = _platformString();

      await Supabase.instance.client.from('user_fcm_tokens').upsert(
        <String, dynamic>{
          'user_id':    uid,
          'fcm_token':  token,
          'platform':   platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );

      debugPrint('[FcmTokenService] Token registered for $platform.');
    } catch (e) {
      // Non-fatal — app works without notifications.
      debugPrint('[FcmTokenService] Failed to register token: $e');
    }
  }

  static String _platformString() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS     => 'ios',
      TargetPlatform.macOS   => 'ios',
      _                      => 'android',
    };
  }
}
