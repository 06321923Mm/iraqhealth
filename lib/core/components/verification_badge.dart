import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, this.showLabel = true});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 8 : 4,
        vertical: showLabel ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.verified, size: 14, color: Color(0xFF1565C0)),
          if (showLabel) ...<Widget>[
            const SizedBox(width: 3),
            Text(
              'موثّق',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1565C0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
