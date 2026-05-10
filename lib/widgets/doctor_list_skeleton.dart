import 'package:flutter/material.dart';

import 'doctor_card_skeleton.dart';

class DoctorListSkeleton extends StatelessWidget {
  const DoctorListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 6,
      itemBuilder: (_, _) => const DoctorCardSkeleton(),
    );
  }
}
