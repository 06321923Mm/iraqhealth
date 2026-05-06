import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1D3557),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: const Color(0xFF607D8B),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
