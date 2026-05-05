import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// شاشة تسجيل الدخول الإلزامي (Google / Facebook) قبل استخدام التطبيق.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService(Supabase.instance.client);
  bool _busy = false;

  void _showErrorSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      await _auth.signInWithGoogle();
      // AuthGate يراقب onAuthStateChange ويتولى الانتقال تلقائياً
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() => _busy = true);
    try {
      await _auth.signInWithFacebook();
      // AuthGate يراقب onAuthStateChange ويتولى الانتقال تلقائياً
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
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
                        child: Icon(
                          Icons.medical_services_rounded,
                          size: 52,
                          color: accent,
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
                      _SocialButton(
                        onPressed: _busy ? null : _signInWithGoogle,
                        icon: FontAwesomeIcons.google,
                        label: 'الدخول عبر جوجل',
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4285F4),
                        borderColor: const Color(0xFFE0E0E0),
                      ),
                      const SizedBox(height: 14),
                      _SocialButton(
                        onPressed: _busy ? null : _signInWithFacebook,
                        icon: FontAwesomeIcons.facebookF,
                        label: 'الدخول عبر فيسبوك',
                        backgroundColor: const Color(0xFF1877F2),
                        foregroundColor: Colors.white,
                        borderColor: const Color(0xFF1877F2),
                      ),
                      if (_busy) ...<Widget>[
                        const SizedBox(height: 28),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      ],
                      const SizedBox(height: 36),
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
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final VoidCallback? onPressed;
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
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: onPressed == null ? 0 : 1,
          shadowColor: Colors.black26,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
