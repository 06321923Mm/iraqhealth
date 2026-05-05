import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../splash_screen.dart';
import 'login_screen.dart';

/// يعرض [LoginScreen] عند عدم وجود جلسة، وإلا يتابع التدفق الحالي.
/// يراقب دورة حياة التطبيق لاصطياد جلسة OAuth عند العودة من المتصفح.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // عند العودة من المتصفح بعد OAuth — يجبر supabase_flutter على فحص الجلسة
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        Supabase.instance.client.auth.refreshSession().ignore();
      } else {
        Supabase.instance.client.auth.getUser().ignore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (BuildContext context, AsyncSnapshot<AuthState> snapshot) {
        if (!snapshot.hasData) {
          // إذا كانت هناك جلسة محفوظة نعرض SplashScreen مباشرة بدون وميض
          if (Supabase.instance.client.auth.currentSession != null) {
            return const SplashScreen();
          }
          return const LoginScreen();
        }

        final Session? session =
            snapshot.data!.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const SplashScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
