// ✅ UPDATED 2026-05-09
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'crashlytics_service.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/app_env.dart';

/// OAuth **Web** — لـ `serverClientId` وSupabase (لا يُستخدم كـ `clientId` على الموبايل).
const String kGoogleWebServerClientId =
    '63970501606-ntgc1l1ercd3jj2uskn1kfs8tjo54vd7.apps.googleusercontent.com';

/// OAuth **iOS / macOS** — يُستخدم كـ `clientId` لـ [GoogleSignIn] داخل التطبيق على آبل.
const String kGoogleIosClientId =
    '63970501606-j9r8789mcj1i1j7fvt2c0gj50s247ejr.apps.googleusercontent.com';

/// تسجيل الدخول عبر Google وFacebook مع Supabase Auth.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  static const List<String> _googleScopes = <String>[
    'openid',
    'email',
    'profile',
  ];

  /// [google_sign_in] 7.x: [GoogleSignIn.initialize] once per process.
  bool _embeddedGoogleConfigured = false;

  String get _googleServerClientId => AppEnv.googleWebClientId.isNotEmpty
      ? AppEnv.googleWebClientId
      : kGoogleWebServerClientId;

  String get _iosClientId => AppEnv.googleIosClientId.isNotEmpty
      ? AppEnv.googleIosClientId
      : kGoogleIosClientId;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  // Android 14+ (API 34+) broke the legacy onActivityResult flow used by
  // google_sign_in_android <7.x, so we fall back to the OAuth browser flow
  // on Android and keep the embedded SDK only for iOS/macOS.
  bool get _usesEmbeddedGoogleSdk =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _ensureEmbeddedGoogleConfigured() async {
    if (_embeddedGoogleConfigured) return;
    await GoogleSignIn.instance.initialize(
      clientId: _iosClientId,
      serverClientId: _googleServerClientId,
    );
    _embeddedGoogleConfigured = true;
  }

  /// Google:
  /// - **الويب**: OAuth في المتصفح (قيود المنصّة؛ غير جزء من تطبيقات المتجر المحلية).
  /// - **Android / iOS / macOS**: [GoogleSignIn] داخل التطبيق (حوار النظام / SDK) ثم [signInWithIdToken] لـ Supabase.
  /// - **ويندوز / لينكس**: OAuth عبر رابط خارجي (لا يوجد `google_sign_in` رسمي لهما).
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final bool opened = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _webRedirectTo(),
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      if (!opened) {
        throw const AuthException('تعذّر فتح نافذة تسجيل الدخول.');
      }
      return;
    }

    if (_usesEmbeddedGoogleSdk) {
      await _ensureEmbeddedGoogleConfigured();
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // لا توجد جلسة سابقة — نكمل
      }

      try {
        final GoogleSignInAccount account = await GoogleSignIn.instance
            .authenticate(scopeHint: _googleScopes);

        final GoogleSignInAuthentication auth = account.authentication;
        final String? idToken = auth.idToken;

        if (idToken == null || idToken.isEmpty) {
          throw const AuthException(
            'تعذّر الحصول على رمز التعريف. '
            'تأكد أن SHA-1 مضاف في Google Cloud Console وأن serverClientId يطابق معرّف عميل Web.',
          );
        }

        await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
        return;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted ||
            e.code == GoogleSignInExceptionCode.uiUnavailable) {
          return;
        }
        CrashlyticsService.instance.logAuthFailure('google', e);
        throw AuthException(
          'فشل تسجيل الدخول بجوجل (${e.code.name}): '
          '${e.description ?? e.toString()}',
        );
      }
    }

    try {
      // Android / Windows / Linux — browser PKCE flow
      // LaunchMode.platformDefault is more reliable than externalApplication
      // on Android 14+ (API 34) because the OS selects the best Custom Tab
      // integration automatically without forcing an external browser.
      final bool opened = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppEnv.oauthRedirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      if (!opened) {
        throw const AuthException('تعذّر فتح نافذة تسجيل الدخول.');
      }
    } on PlatformException catch (e) {
      // sign_in_canceled (iOS/macOS) and 12501 (Google Play Services on Android)
      // both mean the user dismissed the sign-in UI — treat as silent no-op.
      if (e.code == 'sign_in_canceled' || e.code == '12501') return;
      CrashlyticsService.instance.logAuthFailure('google', e);
      throw AuthException(
        'تعذّر تسجيل الدخول بحساب Google (${e.code}). '
        'تأكد من الاتصال بالإنترنت.',
      );
    }
  }

  Future<void> signInWithFacebook() async {
    final bool opened = await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: kIsWeb ? _webRedirectTo() : AppEnv.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw const AuthException('تعذّر فتح المتصفح لتسجيل الدخول.');
    }
  }

  Future<void> signOut() async {
    if (_usesEmbeddedGoogleSdk && _embeddedGoogleConfigured) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // لا جلسة Google محلية
      }
    }
    await _client.auth.signOut();
  }

  String _webRedirectTo() {
    // استخدم OAUTH_REDIRECT_URL إن كان https (مُمرَّر عبر --dart-define في CI للإنتاج).
    // إن كان deep-link للموبايل أو فارغاً، ارجع إلى Uri.base الديناميكي.
    final String envUrl = AppEnv.oauthRedirectUrl;
    if (envUrl.startsWith('https://')) return envUrl;

    final Uri base = Uri.base;
    if (base.hasEmptyPath || base.path == '/') {
      return '${base.origin}/';
    }
    return base.origin + (base.path.endsWith('/') ? base.path : '${base.path}/');
  }
}
