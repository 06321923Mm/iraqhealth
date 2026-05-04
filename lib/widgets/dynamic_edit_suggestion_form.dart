import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigation.dart';
import '../supabase_write_errors.dart';
import '../edit_suggestion/arabic_column_label.dart';
import '../edit_suggestion/column_edit_semantics.dart';
import '../edit_suggestion/dynamic_report_insert.dart';
import '../edit_suggestion/edit_suggestion_schema_service.dart';
import '../edit_suggestion/google_maps_coords_parser.dart';
import '../edit_suggestion/schema_models.dart';
import '../location_picker_screen.dart';

/// RTL form: Arabic labels only in the field selector; values follow column types.
class DynamicEditSuggestionForm extends StatefulWidget {
  const DynamicEditSuggestionForm({
    super.key,
    required this.formKey,
    required this.bundle,
    required this.schemaService,
    required this.targetPkValue,
    required this.doctorNameSnapshot,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.statusPendingValue,
    required this.onSubmitted,
    this.compactIntro = false,
  });

  /// Must wrap this widget (and any sibling fields validated together).
  final GlobalKey<FormState> formKey;
  final EditSuggestionSchemaBundle bundle;
  final EditSuggestionSchemaService schemaService;
  final Object targetPkValue;
  final String doctorNameSnapshot;
  final double initialLatitude;
  final double initialLongitude;
  final String statusPendingValue;
  final VoidCallback onSubmitted;
  final bool compactIntro;

  @override
  State<DynamicEditSuggestionForm> createState() =>
      _DynamicEditSuggestionFormState();
}

class _DynamicEditSuggestionFormState extends State<DynamicEditSuggestionForm> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _whereWrongController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _mapsLinkController = TextEditingController();

  List<SchemaColumn> _choices = const <SchemaColumn>[];
  SchemaColumn? _selected;
  bool _submitting = false;
  double? _pickedLat;
  double? _pickedLng;
  List<Map<String, String>> _fkOptions = const <Map<String, String>>[];
  Timer? _fkDebounce;

  @override
  void initState() {
    super.initState();
    _choices = reporterSelectableColumns(widget.bundle.primaryTarget);
    if (_choices.isNotEmpty) {
      _selected = _choices.first;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selected?.isUuidType == true) {
        _refreshFkOptions('');
      }
    });
  }

  @override
  void dispose() {
    _fkDebounce?.cancel();
    _whereWrongController.dispose();
    _valueController.dispose();
    _mapsLinkController.dispose();
    super.dispose();
  }

  bool get _coordMode {
    final SchemaColumn? s = _selected;
    if (s == null) {
      return false;
    }
    return isCoordinateLikeColumn(s) || isMapsLinkOrLocationTextColumn(s);
  }

  bool get _uuidMode {
    final SchemaColumn? s = _selected;
    return s != null && s.isUuidType;
  }

  Future<void> _refreshFkOptions(String q) async {
    final EditSuggestionTarget? t = widget.bundle.primaryTarget;
    final SchemaColumn? s = _selected;
    if (t == null || s == null || !_uuidMode) {
      return;
    }
    final List<Map<String, String>> opts = await widget.schemaService.loadFkOptions(
      refSchema: t.refSchema,
      refTable: t.refTable,
      pkColumn: s.columnName,
      labelColumn: t.defaultLabelColumn,
      search: q,
    );
    if (mounted) {
      setState(() => _fkOptions = opts);
    }
  }

  void _onValueChangedForFk(String v) {
    if (!_uuidMode) {
      return;
    }
    _fkDebounce?.cancel();
    _fkDebounce = Timer(const Duration(milliseconds: 320), () {
      _refreshFkOptions(v.trim());
    });
  }

  Future<void> _openMap() async {
    final LocationPickResult? picked =
        await Navigator.of(context).push<LocationPickResult>(
      buildAdaptiveRtlRoute<LocationPickResult>(
        LocationPickerScreen(
          initialLatitude: _pickedLat ?? widget.initialLatitude,
          initialLongitude: _pickedLng ?? widget.initialLongitude,
          title: 'تحديد الموقع الصحيح',
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _pickedLat = picked.latitude;
      _pickedLng = picked.longitude;
      final StringBuffer buf = StringBuffer();
      final String? line = picked.addressLine?.trim();
      if (line != null && line.isNotEmpty) {
        buf.writeln(line);
      }
      buf.write(
        '${picked.latitude.toStringAsFixed(6)}, ${picked.longitude.toStringAsFixed(6)}',
      );
      _valueController.text = buf.toString();
    });
  }

  void _applyMapsLink() {
    final ({double lat, double lng})? p =
        GoogleMapsCoordsParser.tryParsePair(_mapsLinkController.text);
    if (p == null) {
      return;
    }
    setState(() {
      _pickedLat = p.lat;
      _pickedLng = p.lng;
      _valueController.text =
          '${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)}';
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    if (!(widget.formKey.currentState?.validate() ?? false)) {
      return;
    }
    final SchemaColumn? sel = _selected;
    if (sel == null) {
      return;
    }
    FocusScope.of(context).unfocus();

    if (_coordMode) {
      if (_pickedLat == null || _pickedLng == null) {
        final ({double lat, double lng})? fromLink =
            GoogleMapsCoordsParser.tryParsePair(_mapsLinkController.text) ??
                GoogleMapsCoordsParser.tryParsePair(_valueController.text);
        if (fromLink != null) {
          _pickedLat = fromLink.lat;
          _pickedLng = fromLink.lng;
        }
      }
      if (_pickedLat == null || _pickedLng == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('حدد الموقع على الخريطة أو الصق رابط خرائط Google صالح.'),
          ),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    final Map<String, dynamic> row = DynamicReportInsertBuilder(widget.bundle).build(
      targetPkValue: widget.targetPkValue,
      doctorNameSnapshot: widget.doctorNameSnapshot,
      selectedField: sel,
      whereWrongText: _whereWrongController.text,
      suggestedText: _valueController.text,
      statusPendingValue: widget.statusPendingValue,
      suggestedLatitude: _coordMode ? _pickedLat : null,
      suggestedLongitude: _coordMode ? _pickedLng : null,
    );

    try {
      await _supabase.from(widget.bundle.reportsTable).insert(row);
      widget.onSubmitted();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('تعذر الإرسال: ${reportInsertErrorMessage(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.bundle.ok || widget.bundle.primaryTarget == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'تعذر تحميل هيكل قاعدة البيانات. تأكد من تطبيق أحدث migrations على Supabase.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_choices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('لا توجد أعمدة متاحة للاقتراح.'),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!widget.compactIntro) ...<Widget>[
              const Text(
                'اقتراح تعديل على المعلومات',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1D3557),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر الحقل من القائمة (الأسماء بالعربي)، ثم اكتب التصحيح أو حدد الموقع.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF718096),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<SchemaColumn>(
              key: ValueKey<String>(_selected?.columnName ?? ''),
              initialValue: _selected,
              decoration: const InputDecoration(
                labelText: 'أي حقل يحتاج تصحيحاً؟',
                filled: true,
                fillColor: Color(0xFFF2F7FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
              ),
              items: _choices
                  .map(
                    (SchemaColumn c) => DropdownMenuItem<SchemaColumn>(
                      value: c,
                      child: Text(arabicLabelForColumn(c)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (SchemaColumn? v) {
                if (v == null) {
                  return;
                }
                setState(() {
                  _selected = v;
                  _pickedLat = null;
                  _pickedLng = null;
                  _fkOptions = const <Map<String, String>>[];
                  if (_uuidMode) {
                    _refreshFkOptions('');
                  }
                });
              },
            ),
            if (_coordMode) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _openMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  _pickedLat != null
                      ? 'تعديل الموقع على الخريطة'
                      : 'فتح الخريطة وتحديد الموقع الصحيح',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _mapsLinkController,
                decoration: const InputDecoration(
                  labelText: 'أو الصق رابط خرائط Google',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                onFieldSubmitted: (_) => _applyMapsLink(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _submitting ? null : _applyMapsLink,
                  child: const Text('استخراج الإحداثيات من الرابط'),
                ),
              ),
            ],
            if (_uuidMode) ...<Widget>[
              const SizedBox(height: 8),
              TextFormField(
                controller: _valueController,
                onChanged: _onValueChangedForFk,
                decoration: const InputDecoration(
                  labelText: 'معرّف القيمة (UUID)',
                  filled: true,
                  fillColor: Color(0xFFF2F7FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? v) {
                  final String t = v?.trim() ?? '';
                  if (t.length < 32) {
                    return 'أدخل UUID كاملاً أو اختر من القائمة';
                  }
                  return null;
                },
              ),
              if (_fkOptions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _fkOptions.length,
                    itemBuilder: (BuildContext ctx, int i) {
                      final Map<String, String> o = _fkOptions[i];
                      return ListTile(
                        dense: true,
                        title: Text(o['label'] ?? ''),
                        subtitle: Text(o['id'] ?? ''),
                        onTap: () {
                          setState(() {
                            _valueController.text = o['id'] ?? '';
                          });
                        },
                      );
                    },
                  ),
                ),
            ],
            if (!_uuidMode) ...<Widget>[
              const SizedBox(height: 12),
              TextFormField(
                controller: _valueController,
                maxLines: _coordMode ? 3 : 4,
                keyboardType: _selected != null && _selected!.isNumericType && !_coordMode
                    ? TextInputType.number
                    : TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: _coordMode
                      ? 'وصف / ملاحظات على الموقع (اختياري)'
                      : 'ما التصحيح المقترح؟',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: const Color(0xFFF2F7FC),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                validator: (String? value) {
                  if (_coordMode) {
                    return null;
                  }
                  if (value == null || value.trim().length < 2) {
                    return 'اذكر التصحيح المقترح';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _whereWrongController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText:
                    'وين يظهر الخطأ بالضبط؟ (مثلاً: مربع الهاتف، سطر التخصص)',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Color(0xFFF2F7FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
              ),
              validator: (String? value) {
                if (value == null || value.trim().length < 3) {
                  return 'حدد مكان الخطأ في البطاقة (3 أحرف على الأقل)';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'جارٍ الإرسال...' : 'إرسال الاقتراح'),
            ),
          ],
        ),
    );
  }
}
