import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color primary     = Color(0xFF0F172A);
  static const Color accent      = Color(0xFFC8A96B);
  static const Color accentLight = Color(0xFFF0E6C8);
  static const Color background  = Color(0xFFF8FAFC);
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecond  = Color(0xFF64748B);
  static const Color textHint    = Color(0xFF94A3B8);
  static const Color border      = Color(0xFFE2E8F0);
  static const Color borderFocus = Color(0xFFC8A96B);

  static const Color statusOnline = Color(0xFF10B981);
  static const Color statusBusy   = Color(0xFFF59E0B);
  static const Color statusClosed = Color(0xFFEF4444);

  static const Color chipActive   = Color(0xFF0F172A);
  static const Color chipInactive = Color(0xFFF1F5F9);
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle heading1(BuildContext ctx) => GoogleFonts.cairo(
        fontSize: _s(ctx, 20),
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle heading2(BuildContext ctx) => GoogleFonts.cairo(
        fontSize: _s(ctx, 17),
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle body(BuildContext ctx) => GoogleFonts.cairo(
        fontSize: _s(ctx, 14),
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle caption(BuildContext ctx) => GoogleFonts.cairo(
        fontSize: _s(ctx, 12),
        fontWeight: FontWeight.w400,
        color: AppColors.textSecond,
      );

  static TextStyle label(BuildContext ctx) => GoogleFonts.cairo(
        fontSize: _s(ctx, 13),
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static double _s(BuildContext ctx, double base) {
    final double w = MediaQuery.of(ctx).size.width;
    if (w < 360) return base * 0.9;
    if (w > 420) return base * 1.05;
    return base;
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    textTheme: GoogleFonts.cairoTextTheme(),
    fontFamily: GoogleFonts.cairo().fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onPrimary: Colors.white,
      onSecondary: AppColors.primary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.chipInactive,
      selectedColor: AppColors.chipActive,
      side: BorderSide(color: AppColors.border),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      labelPadding: EdgeInsets.zero,
      shape: StadiumBorder(),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
