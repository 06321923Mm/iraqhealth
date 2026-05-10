import 'package:flutter/foundation.dart' show immutable;

import 'doctor_constants.dart';

/// تصنيف المجال الطبي في عمود [`spec`] (طبيب، أشعة…)، متطابق في كل النماذج.
enum MedicalFieldType {
  physician,
  radiology,
  dentist,
  pharmacy,
  lab,
}

/// حالة «مجموعة الخمس خيارات + تخصص الطبيب» قبل تحويلها إلى سلسلة [spec].
@immutable
class MedicalCategorySnapshot {
  const MedicalCategorySnapshot({
    this.category,
    this.physicianDropdownSelection,
    this.physicianUseCustomEntry = false,
    this.physicianCustomText = '',
  });

  /// لم يُختر بعد أي تصنيف رئيسي.
  factory MedicalCategorySnapshot.empty() =>
      const MedicalCategorySnapshot(category: null);

  factory MedicalCategorySnapshot.fromStoredSpec(String rawSpec) {
    final String trimmed = rawSpec.trim();
    if (trimmed.isEmpty) {
      return MedicalCategorySnapshot.empty();
    }
    if (trimmed == kSpecDentistry) {
      return const MedicalCategorySnapshot(category: MedicalFieldType.dentist);
    }
    if (trimmed == kSpecPharmacy) {
      return const MedicalCategorySnapshot(category: MedicalFieldType.pharmacy);
    }
    if (trimmed == kSpecLaboratory) {
      return const MedicalCategorySnapshot(category: MedicalFieldType.lab);
    }
    if (trimmed == kSpecRadiology ||
        kLegacyRadiologySpecValues.contains(trimmed)) {
      return const MedicalCategorySnapshot(category: MedicalFieldType.radiology);
    }
    if (kPhysicianSpecializations.contains(trimmed)) {
      return MedicalCategorySnapshot(
        category: MedicalFieldType.physician,
        physicianDropdownSelection: trimmed,
      );
    }
    return MedicalCategorySnapshot(
      category: MedicalFieldType.physician,
      physicianUseCustomEntry: true,
      physicianDropdownSelection: kFormDropdownCustomSentinel,
      physicianCustomText: trimmed,
    );
  }

  final MedicalFieldType? category;
  /// قيمة من [kPhysicianSpecializations]، أو [kFormDropdownCustomSentinel] عند الإدخال اليدوي.
  final String? physicianDropdownSelection;
  final bool physicianUseCustomEntry;
  final String physicianCustomText;

  bool validateBeforeEncode() {
    final MedicalFieldType? c = category;
    if (c == null) {
      return false;
    }
    if (c != MedicalFieldType.physician) {
      return true;
    }
    if (physicianUseCustomEntry) {
      return physicianCustomText.trim().length >= 2;
    }
    final String? s = physicianDropdownSelection;
    return s != null &&
        s.isNotEmpty &&
        s != kFormDropdownCustomSentinel;
  }

  /// سلسلة [spec] المخزّنة؛ فارغة إذا لم يكتمل الاختيار.
  String toStoredSpec() {
    if (!validateBeforeEncode()) {
      return '';
    }
    switch (category!) {
      case MedicalFieldType.physician:
        return physicianUseCustomEntry
            ? physicianCustomText.trim()
            : (physicianDropdownSelection ?? '').trim();
      case MedicalFieldType.radiology:
        return kSpecRadiology;
      case MedicalFieldType.dentist:
        return kSpecDentistry;
      case MedicalFieldType.pharmacy:
        return kSpecPharmacy;
      case MedicalFieldType.lab:
        return kSpecLaboratory;
    }
  }
}
