import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
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

  GoogleSignIn? _googleSignIn;

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

  GoogleSignIn _googleSignInEmbedded() {
    if (!_usesEmbeddedGoogleSdk) {
      throw UnsupportedError('Google SDK محلي غير مدعوم على هذه المنصة.');
    }
    _googleSignIn ??= switch (defaultTargetPlatform) {
      TargetPlatform.android => GoogleSignIn(
          serverClientId: _googleServerClientId,
          scopes: _googleScopes,
        ),
      TargetPlatform.iOS || TargetPlatform.macOS => GoogleSignIn(
          clientId: _iosClientId,
          serverClientId: _googleServerClientId,
          scopes: _googleScopes,
        ),
      _ => throw UnsupportedError('Google SDK محلي غير مدعوم على هذه المنصة.'),
    };
    return _googleSignIn!;
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
      final GoogleSignIn googleSignIn = _googleSignInEmbedded();
      try {
        await googleSignIn.signOut();
      } catch (_) {
        // لا توجد جلسة سابقة — نكمل
      }

      GoogleSignInAccount? account;
      try {
        account = await googleSignIn.signIn();
      } on PlatformException catch (e) {
        // sign_in_canceled → المستخدم أغلق النافذة
        if (e.code == 'sign_in_canceled') return;
        throw AuthException('فشل تسجيل الدخول بجوجل (${e.code}): ${e.message}');
      }

      // null = المستخدم أغلق نافذة الاختيار
      if (account == null) return;

      final GoogleSignInAuthentication auth = await account.authentication;
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
        accessToken: auth.accessToken,
      );
      return;
    }

    final bool opened = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AppEnv.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw const AuthException('تعذّر فتح نافذة تسجيل الدخول.');
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
    if (_usesEmbeddedGoogleSdk) {
      try {
        await _googleSignInEmbedded().signOut();
      } catch (_) {
        // لا جلسة Google محلية
      }
    }
    _googleSignIn = null;
    await _client.auth.signOut();
  }

  String _webRedirectTo() {
    final Uri base = Uri.base;
    if (base.hasEmptyPath || base.path == '/') {
      return '${base.origin}/';
    }
    return base.origin + (base.path.endsWith('/') ? base.path : '${base.path}/');
  }
}
