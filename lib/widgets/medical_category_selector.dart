import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_endpoints.dart';
import '../doctor_constants.dart';
import '../medical_field.dart';

/// Single live suggestion row from `suggest_specialization(input_text)`.
class SpecializationSuggestion {
  const SpecializationSuggestion({
    required this.id,
    required this.canonicalName,
    required this.score,
  });

  factory SpecializationSuggestion.fromJson(Map<String, dynamic> json) {
    final dynamic rawId = json['id'];
    final dynamic rawScore = json['similarity_score'];
    return SpecializationSuggestion(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0,
      canonicalName: (json['canonical_name'] ?? '').toString(),
      score: rawScore is num ? rawScore.toDouble() : 0.0,
    );
  }

  final int id;
  final String canonicalName;
  final double score;
}

/// مجموعة الخمس خيارات الرئيسية + قائمة تخصص الطبيب (بنفس المنطق في الأدمن والمستخدم واقتراح التعديل).
class MedicalCategorySelector extends StatefulWidget {
  const MedicalCategorySelector({
    super.key,
    required this.initialStoredSpec,
    required this.decorateDropdownField,
    this.showIntroLabels = true,
    this.introHeadingStyle,
    this.tileRadius = 12,
    this.onComposedStoredSpecChanged,
    this.onSpecializationIdChanged,
    this.initialSpecializationId,
  });

  /// قيمة `spec` الحالية من قاعدة البيانات (أو فارغة عند إضافة جديدة).
  final String initialStoredSpec;

  /// زخرفة حقول القائمة المنسدلة للتخصص والحقول المشابهة.
  final InputDecoration Function(String labelText) decorateDropdownField;

  /// عنوان «المجال الطبي» وشرح التخصص عند الحاجة.
  final bool showIntroLabels;
  final TextStyle? introHeadingStyle;

  final double tileRadius;

  /// يُستدعى عند تغيّر [`spec`] المُجمَّع (مثلاً لمزامنة `TextEditingController` في اقتراح التعديل).
  final ValueChanged<String>? onComposedStoredSpecChanged;

  /// يُستدعى عند تغيّر التخصص المُختار من جدول specializations.
  final ValueChanged<int?>? onSpecializationIdChanged;

  /// قيمة [specialization_id] الأولية (عند تحرير عيادة موجودة).
  final int? initialSpecializationId;

  @override
  State<MedicalCategorySelector> createState() =>
      MedicalCategorySelectorState();
}

class MedicalCategorySelectorState extends State<MedicalCategorySelector> {
  late final TextEditingController _physicianCustomCtrl;

  MedicalFieldType? _category;
  String? _physicianDropdownValue;
  bool _physicianUseCustom = false;

  int? _specializationId;
  Timer? _suggestionsDebounce;
  List<SpecializationSuggestion> _liveSuggestions =
      const <SpecializationSuggestion>[];
  bool _loadingSuggestions = false;

  /// Returns the currently-resolved specialization_id (canonical match or null when free-text).
  int? get specializationId => _specializationId;

  @override
  void initState() {
    super.initState();
    _physicianCustomCtrl = TextEditingController();
    _physicianCustomCtrl.addListener(_onCustomSpecChanged);
    _specializationId = widget.initialSpecializationId;
    reloadFromStoredSpec(widget.initialStoredSpec);
  }

  @override
  void didUpdateWidget(MedicalCategorySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStoredSpec != widget.initialStoredSpec) {
      reloadFromStoredSpec(widget.initialStoredSpec);
    }
    if (oldWidget.initialSpecializationId != widget.initialSpecializationId) {
      _specializationId = widget.initialSpecializationId;
    }
  }

  @override
  void dispose() {
    _suggestionsDebounce?.cancel();
    _physicianCustomCtrl.removeListener(_onCustomSpecChanged);
    _physicianCustomCtrl.dispose();
    super.dispose();
  }

  void _onCustomSpecChanged() {
    widget.onComposedStoredSpecChanged?.call(composeStoredSpec());
    _scheduleSuggestionsLookup(_physicianCustomCtrl.text);
  }

  /// إعادة قراءة قيمة مخزّنة من الخادم (بعد تحميل العيادة أو إعادة تعيين النموذج).
  void reloadFromStoredSpec(String spec) {
    final MedicalCategorySnapshot snap =
        MedicalCategorySnapshot.fromStoredSpec(spec);
    _category = snap.category;
    _physicianUseCustom = snap.physicianUseCustomEntry;
    _physicianDropdownValue = snap.physicianDropdownSelection;
    _physicianCustomCtrl.text = snap.physicianCustomText;
    if (mounted) {
      setState(() {});
    }
    widget.onComposedStoredSpecChanged?.call(composeStoredSpec());
    _resolveSpecializationIdFromComposed();
  }

  MedicalCategorySnapshot _snapshotNow() {
    return MedicalCategorySnapshot(
      category: _category,
      physicianDropdownSelection: _physicianUseCustom
          ? kFormDropdownCustomSentinel
          : _physicianDropdownValue,
      physicianUseCustomEntry: _physicianUseCustom,
      physicianCustomText: _physicianCustomCtrl.text,
    );
  }

  String composeStoredSpec() => _snapshotNow().toStoredSpec();

  bool validateSelection() => _snapshotNow().validateBeforeEncode();

  void _setCategory(MedicalFieldType type) {
    setState(() {
      _category = type;
      if (type != MedicalFieldType.physician) {
        _physicianDropdownValue = null;
        _physicianUseCustom = false;
        _physicianCustomCtrl.clear();
        _liveSuggestions = const <SpecializationSuggestion>[];
      }
    });
    widget.onComposedStoredSpecChanged?.call(composeStoredSpec());
    _resolveSpecializationIdFromComposed();
  }

  void _scheduleSuggestionsLookup(String input) {
    _suggestionsDebounce?.cancel();
    final String trimmed = input.trim();
    if (trimmed.length < 2 || !_physicianUseCustom) {
      if (_liveSuggestions.isNotEmpty) {
        setState(() => _liveSuggestions = const <SpecializationSuggestion>[]);
      }
      return;
    }
    _suggestionsDebounce =
        Timer(const Duration(milliseconds: 280), () => _fetchSuggestions(trimmed));
  }

  Future<void> _fetchSuggestions(String input) async {
    if (!mounted) return;
    setState(() => _loadingSuggestions = true);
    try {
      final dynamic res = await Supabase.instance.client
          .rpc(AppEndpoints.suggestSpecialization,
              params: <String, dynamic>{'input_text': input});
      if (!mounted) return;
      final List<SpecializationSuggestion> next = (res is List)
          ? res
              .whereType<Map<String, dynamic>>()
              .map(SpecializationSuggestion.fromJson)
              .toList(growable: false)
          : const <SpecializationSuggestion>[];
      setState(() {
        _liveSuggestions = next;
        _loadingSuggestions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveSuggestions = const <SpecializationSuggestion>[];
        _loadingSuggestions = false;
      });
    }
  }

  /// عند الاختيار من الاقتراحات: نملأ النص ونعيّن المعرّف القانوني.
  void _applySuggestion(SpecializationSuggestion s) {
    setState(() {
      _physicianUseCustom = true;
      _physicianDropdownValue = kFormDropdownCustomSentinel;
      _physicianCustomCtrl.text = s.canonicalName;
      _liveSuggestions = const <SpecializationSuggestion>[];
      _specializationId = s.id;
    });
    widget.onComposedStoredSpecChanged?.call(composeStoredSpec());
    widget.onSpecializationIdChanged?.call(_specializationId);
  }

  /// Resolves [specialization_id] from the currently-composed spec by exact match.
  Future<void> _resolveSpecializationIdFromComposed() async {
    final String composed = composeStoredSpec().trim();
    if (composed.isEmpty) {
      _setSpecializationId(null);
      return;
    }
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from(AppEndpoints.specializations)
          .select('id')
          .eq('canonical_name', composed)
          .limit(1);
      if (!mounted) return;
      if (rows.isNotEmpty) {
        final dynamic raw = (rows.first as Map<String, dynamic>)['id'];
        final int? id =
            raw is int ? raw : int.tryParse(raw?.toString() ?? '');
        _setSpecializationId(id);
      } else {
        _setSpecializationId(null);
      }
    } catch (_) {
      _setSpecializationId(null);
    }
  }

  void _setSpecializationId(int? next) {
    if (_specializationId != next) {
      _specializationId = next;
      widget.onSpecializationIdChanged?.call(next);
    }
  }

  Widget _tile(String title, MedicalFieldType type) {
    final bool sel = _category == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: sel ? const Color(0xFFE3F2FD) : const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(widget.tileRadius),
        child: ListTile(
          dense: true,
          onTap: () => _setCategory(type),
          leading: Icon(
            sel
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: sel ? const Color(0xFF1976D2) : const Color(0xFF94A3B8),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle headingStyle = widget.introHeadingStyle ??
        const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Color(0xFF475569),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showIntroLabels) ...<Widget>[
          Text('المجال الطبي *', style: headingStyle),
          const SizedBox(height: 6),
        ],
        _tile('طبيب', MedicalFieldType.physician),
        _tile('اشعة وسونار', MedicalFieldType.radiology),
        _tile('طبيب أسنان', MedicalFieldType.dentist),
        _tile('صيدلية', MedicalFieldType.pharmacy),
        _tile('مختبر', MedicalFieldType.lab),
        if (_category == MedicalFieldType.physician) ...<Widget>[
          SizedBox(height: widget.showIntroLabels ? 10 : 6),
          Text('التخصص *', style: headingStyle),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>(
                'phys_${_physicianUseCustom}_$_physicianDropdownValue'),
            initialValue: _physicianUseCustom
                ? kFormDropdownCustomSentinel
                : _physicianDropdownValue,
            isExpanded: true,
            decoration: widget.decorateDropdownField('اختر التخصص'),
            items: <DropdownMenuItem<String>>[
              ...kPhysicianSpecializations.map(
                (String s) => DropdownMenuItem<String>(
                  value: s,
                  child: Text(s),
                ),
              ),
              const DropdownMenuItem<String>(
                value: kFormDropdownCustomSentinel,
                child: Text('إضافة تخصص جديد'),
              ),
            ],
            onChanged: (String? v) {
              if (v == null) return;
              setState(() {
                if (v == kFormDropdownCustomSentinel) {
                  _physicianUseCustom = true;
                  _physicianDropdownValue = kFormDropdownCustomSentinel;
                } else {
                  _physicianUseCustom = false;
                  _physicianDropdownValue = v;
                  _liveSuggestions = const <SpecializationSuggestion>[];
                }
              });
              widget.onComposedStoredSpecChanged?.call(composeStoredSpec());
              _resolveSpecializationIdFromComposed();
            },
          ),
          if (_physicianUseCustom) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              controller: _physicianCustomCtrl,
              decoration:
                  widget.decorateDropdownField('اكتب التخصص الجديد *'),
            ),
            if (_loadingSuggestions)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_liveSuggestions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                'هل تقصد:',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF607D8B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _liveSuggestions
                    .map(
                      (SpecializationSuggestion s) => ActionChip(
                        backgroundColor: const Color(0xFFE3F2FD),
                        side: const BorderSide(color: Color(0xFF90CAF9)),
                        avatar: const Icon(Icons.auto_awesome,
                            size: 16, color: Color(0xFF1565C0)),
                        label: Text(
                          s.canonicalName,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF0D47A1),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => _applySuggestion(s),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
