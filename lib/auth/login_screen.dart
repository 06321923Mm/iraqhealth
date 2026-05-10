// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// شاشة تسجيل الدخول الإلزامي (Google) قبل استخدام التطبيق.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService(Supabase.instance.client);
  bool _busy = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await _auth.signInWithGoogle();
      // AuthGate يراقب onAuthStateChange ويتولى الانتقال تلقائياً
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'sign_in_canceled' || e.code == '12501') return;
      setState(() => _errorMessage =
          'تعذّر تسجيل الدخول بحساب Google. تأكد من الاتصال بالإنترنت.');
    } on AuthException catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'تعذّر تسجيل الدخول بحساب Google. تأكد من الاتصال بالإنترنت.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'تعذّر تسجيل الدخول بحساب Google. تأكد من الاتصال بالإنترنت.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color deepBlue = Color(0xFF1D3557);
    const Color accent = Color(0xFF42A5F5);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: <Color>[
                Color(0xFFE3F2FD),
                Color(0xFFF7FBFF),
                Color(0xFFE8F5E9),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.medical_services_rounded,
                          size: 52,
                          color: accent,
                          semanticLabel: 'المدار الطبي',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'المدار الطبي',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: deepBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'سجّل الدخول للمتابعة',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          color: const Color(0xFF4A6FA5),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // ── Google Sign-In button ──────────────────────────
                      Semantics(
                        label: 'تسجيل الدخول بحساب Google',
                        button: true,
                        enabled: !_busy,
                        child: _SocialButton(
                          onPressed: _busy ? null : _signInWithGoogle,
                          isLoading: _busy,
                          icon: FontAwesomeIcons.google,
                          label: 'الدخول عبر جوجل',
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF4285F4),
                          borderColor: const Color(0xFFE0E0E0),
                        ),
                      ),

                      // ── Inline error + retry ───────────────────────────
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _busy ? null : _signInWithGoogle,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('حاول مرة أخرى'),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],

                      // ── Future providers divider ───────────────────────
                      const SizedBox(height: 24),
                      Row(
                        children: <Widget>[
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'أو سجّل الدخول بـ',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // TODO: Add Facebook and Apple Sign-In buttons here in future versions
                      Text(
                        'مزيد من خيارات تسجيل الدخول قريباً',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 28),
                      Text(
                        'بالمتابعة، توافق على سياسات مقدّمي الخدمة المعتمدين في مشروعك.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          height: 1.5,
                          color: const Color(0xFF78909C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: BorderSide(color: isLoading ? Colors.grey.shade300 : borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: onPressed == null ? 0 : 1,
          shadowColor: Colors.black26,
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FaIcon(icon, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
