import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class DoctorCardSkeleton extends StatelessWidget {
  const DoctorCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x22000000),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFE0E0E0),
            highlightColor: const Color(0xFFF5F5F5),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Name line
                      _box(width: 160, height: 14),
                      const SizedBox(height: 6),
                      // Specialty chip
                      _box(width: 110, height: 24, radius: 16),
                      const SizedBox(height: 8),
                      // Location line
                      _box(width: 80, height: 11),
                      const SizedBox(height: 10),
                      // Action-button placeholders
                      Row(
                        children: <Widget>[
                          _circle(32),
                          const SizedBox(width: 4),
                          _circle(32),
                          const SizedBox(width: 4),
                          _circle(32),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Avatar circle
                _circle(56),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _box({
    required double width,
    required double height,
    double radius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  static Widget _circle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}
