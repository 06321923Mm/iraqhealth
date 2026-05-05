import 'package:flutter_dotenv/flutter_dotenv.dart';

/// قيم البيئة للـ Supabase وOAuth. تُحمّل من [assets/env/flutter.env] عبر [loadAppEnv].
/// يمكن تجاوزها بـ `--dart-define=KEY=value`.
class AppEnv {
  AppEnv._();

  static const String _defaultSupabaseUrl =
      'https://hygujebngiwemwujjcgm.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh5Z3VqZWJuZ2l3ZW13dWpqY2dtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3Njg1MjAsImV4cCI6MjA5MTM0NDUyMH0.p9hhJZ8L45ZqwQKuq5TCPWEa2xxBNl0AqHPQUjP1Xvs';

  static String _fromDefine(String key) {
    const Map<String, String> defines = <String, String>{
      'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
      'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
      'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      'GOOGLE_ANDROID_CLIENT_ID':
          String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID'),
      'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
      'OAUTH_REDIRECT_URL': String.fromEnvironment('OAUTH_REDIRECT_URL'),
    };
    return defines[key] ?? '';
  }

  static String _firstNonEmpty(List<String> candidates) {
    for (final String s in candidates) {
      final String t = s.trim();
      if (t.isNotEmpty) {
        return t;
      }
    }
    return '';
  }

  /// يُستدعى من [main] بعد [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> loadAppEnv() async {
    await dotenv.load(fileName: 'assets/env/flutter.env');
  }

  static String get supabaseUrl => _firstNonEmpty(<String>[
        _fromDefine('SUPABASE_URL'),
        dotenv.env['SUPABASE_URL'] ?? '',
        _defaultSupabaseUrl,
      ]);

  static String get supabaseAnonKey => _firstNonEmpty(<String>[
        _fromDefine('SUPABASE_ANON_KEY'),
        dotenv.env['SUPABASE_ANON_KEY'] ?? '',
        _defaultSupabaseAnonKey,
      ]);

  /// معرّف عميل OAuth (Web) من Google Cloud — لـ `GoogleSignIn(serverClientId: ...)`.
  static String get googleWebClientId => _firstNonEmpty(<String>[
        _fromDefine('GOOGLE_WEB_CLIENT_ID'),
        dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '',
      ]);

  /// عميل OAuth من نوع **Android** (لـ `GoogleSignIn(clientId: ...)` على أندرويد).
  static String get googleAndroidClientId => _firstNonEmpty(<String>[
        _fromDefine('GOOGLE_ANDROID_CLIENT_ID'),
        dotenv.env['GOOGLE_ANDROID_CLIENT_ID'] ?? '',
      ]);

  /// عميل OAuth من نوع **iOS** (لـ `GoogleSignIn(clientId: ...)` على آيفون).
  static String get googleIosClientId => _firstNonEmpty(<String>[
        _fromDefine('GOOGLE_IOS_CLIENT_ID'),
        dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '',
      ]);

  /// رابط إعادة التوجيه بعد OAuth (Facebook وGoogle على الويب). يجب إضافته في لوحة Supabase.
  static String get oauthRedirectUrl {
    final String custom = _firstNonEmpty(<String>[
      _fromDefine('OAUTH_REDIRECT_URL'),
      dotenv.env['OAUTH_REDIRECT_URL'] ?? '',
    ]);
    if (custom.isNotEmpty) {
      return custom;
    }
    return 'net.iraqhealth.app://login-callback/';
  }
}
