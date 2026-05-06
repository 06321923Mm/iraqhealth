import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum DoctorStatus { online, busy, closed }

extension DoctorStatusX on DoctorStatus {
  String get arabicLabel => switch (this) {
        DoctorStatus.online => 'متاح',
        DoctorStatus.busy   => 'مشغول',
        DoctorStatus.closed => 'مغلق',
      };

  Color get color => switch (this) {
        DoctorStatus.online => const Color(0xFF2E7D32),
        DoctorStatus.busy   => const Color(0xFFE65100),
        DoctorStatus.closed => const Color(0xFFC62828),
      };

  Color get bgColor => switch (this) {
        DoctorStatus.online => const Color(0xFFE8F5E9),
        DoctorStatus.busy   => const Color(0xFFFFF3E0),
        DoctorStatus.closed => const Color(0xFFFFEBEE),
      };

  static DoctorStatus fromString(String? value) => switch (value) {
        'online' => DoctorStatus.online,
        'busy'   => DoctorStatus.busy,
        _        => DoctorStatus.closed,
      };
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final DoctorStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status.arabicLabel,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}
