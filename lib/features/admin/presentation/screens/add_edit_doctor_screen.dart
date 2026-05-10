// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/doctor_coordinates.dart';
import '../../../../doctor_constants.dart';
import '../../../../widgets/doctor_map_location_field.dart';
import '../../../../widgets/medical_category_selector.dart';

/// صفحة إضافة أو تعديل طبيب/عيادة من لوحة الأدمن.
class AddEditDoctorPage extends StatefulWidget {
  const AddEditDoctorPage({super.key, this.doc});

  final Map<String, dynamic>? doc;

  @override
  State<AddEditDoctorPage> createState() => _AddEditDoctorPageState();
}

class _AddEditDoctorPageState extends State<AddEditDoctorPage> {
  final GlobalKey<MedicalCategorySelectorState> _medicalCategoryKey =
      GlobalKey<MedicalCategorySelectorState>();

  late final TextEditingController _areaOtherCtrl;
  late final TextEditingController _basraCustomAreaCtrl;
  late final TextEditingController _textAddrCtrl;
  late final TextEditingController _phCtrl;
  late final TextEditingController _ph2Ctrl;
  late final TextEditingController _notesCtrl;

  late final String _initialMedicalStoredSpec;
  int? _initialSpecializationId;
  int? _selectedSpecializationId;

  String _selectedGove = kGovernorates.first;
  String? _selectedBasraArea;
  bool _basraUseCustomArea = false;
  double? _pickedLatitude;
  double? _pickedLongitude;
  bool _saving = false;

  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _areaOtherCtrl = TextEditingController();
    _basraCustomAreaCtrl = TextEditingController();
    _textAddrCtrl = TextEditingController();
    _phCtrl = TextEditingController();
    _ph2Ctrl = TextEditingController();
    _notesCtrl = TextEditingController();

    final Map<String, dynamic>? doc = widget.doc;
    _initialMedicalStoredSpec = doc?['spec']?.toString() ?? '';
    final dynamic rawSpecId = doc?['specialization_id'];
    _initialSpecializationId = rawSpecId is int
        ? rawSpecId
        : int.tryParse(rawSpecId?.toString() ?? '');
    _selectedSpecializationId = _initialSpecializationId;

    if (doc != null) {
      _nameCtrl.text = doc['name']?.toString() ?? '';
      final String gove = doc['gove']?.toString() ?? kGovernorates.first;
      _selectedGove = kGovernorates.contains(gove) ? gove : kGovernorates.first;
      _initArea(doc['area']?.toString() ?? '', _selectedGove);
      final String addr = doc['addr']?.toString() ?? '';
      if (!addr.startsWith('http://') && !addr.startsWith('https://')) {
        _textAddrCtrl.text = addr;
      }
      _parseNotes(doc['notes']?.toString() ?? '');
      _phCtrl.text = doc['ph']?.toString() ?? '';
      _ph2Ctrl.text = doc['ph2']?.toString() ?? '';
      _pickedLatitude = DoctorCoordinates.readLatitude(doc);
      _pickedLongitude = DoctorCoordinates.readLongitude(doc);
    }
  }

  void _initArea(String area, String gove) {
    final String trimmedArea = area.trim();
    if (gove == 'البصرة') {
      if (kBasraAreas.contains(trimmedArea)) {
        _selectedBasraArea = trimmedArea;
      } else if (trimmedArea.isNotEmpty) {
        _basraUseCustomArea = true;
        _selectedBasraArea = kFormDropdownCustomSentinel;
        _basraCustomAreaCtrl.text = area;
      }
    } else {
      _areaOtherCtrl.text = area;
    }
  }

  void _parseNotes(String raw) {
    final RegExpMatch? m = RegExp(
      r'^العنوان: (.*?)\n\nملاحظات: (.*)',
      dotAll: true,
    ).firstMatch(raw);
    if (m != null) {
      if (_textAddrCtrl.text.isEmpty) _textAddrCtrl.text = m.group(1) ?? '';
      _notesCtrl.text = m.group(2) ?? '';
    } else {
      _notesCtrl.text = raw;
    }
  }

  String _buildArea() {
    if (_selectedGove == 'البصرة') {
      return _basraUseCustomArea
          ? _basraCustomAreaCtrl.text.trim()
          : _selectedBasraArea ?? '';
    }
    return _areaOtherCtrl.text.trim();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _areaOtherCtrl.dispose();
    _basraCustomAreaCtrl.dispose();
    _textAddrCtrl.dispose();
    _phCtrl.dispose();
    _ph2Ctrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.doc != null;
    const Color primaryMedicalBlue = Color(0xFF42A5F5);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit
            ? 'تعديل: ${widget.doc?['name'] ?? ''}'
            : 'إضافة طبيب / عيادة'),
        backgroundColor: primaryMedicalBlue,
        foregroundColor: Colors.white,
        leading: CloseButton(
          color: Colors.white,
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: _dec('اسم الطبيب / المركز *'),
              ),
              const SizedBox(height: 12),
              MedicalCategorySelector(
                key: _medicalCategoryKey,
                initialStoredSpec: _initialMedicalStoredSpec,
                initialSpecializationId: _initialSpecializationId,
                decorateDropdownField: _dec,
                onSpecializationIdChanged: (int? id) =>
                    _selectedSpecializationId = id,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_selectedGove),
                initialValue: _selectedGove,
                isExpanded: true,
                decoration: _dec('المحافظة *'),
                items: kGovernorates
                    .map((String g) => DropdownMenuItem<String>(
                        value: g, child: Text(g)))
                    .toList(),
                onChanged: (String? v) {
                  if (v == null) return;
                  setState(() {
                    _selectedGove = v;
                    if (v != 'البصرة') {
                      _selectedBasraArea = null;
                      _basraUseCustomArea = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_selectedGove == 'البصرة') ...<Widget>[
                const Text('المنطقة *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>(
                      'bs_${_basraUseCustomArea}_$_selectedBasraArea'),
                  initialValue: _basraUseCustomArea
                      ? kFormDropdownCustomSentinel
                      : _selectedBasraArea,
                  isExpanded: true,
                  decoration: _dec('اختر المنطقة'),
                  items: <DropdownMenuItem<String>>[
                    ...kBasraAreas.map((String a) =>
                        DropdownMenuItem<String>(
                            value: a, child: Text(a))),
                    const DropdownMenuItem<String>(
                        value: kFormDropdownCustomSentinel,
                        child: Text('إضافة منطقة جديدة')),
                  ],
                  onChanged: (String? v) {
                    if (v == null) return;
                    setState(() {
                      if (v == kFormDropdownCustomSentinel) {
                        _basraUseCustomArea = true;
                        _selectedBasraArea = kFormDropdownCustomSentinel;
                      } else {
                        _basraUseCustomArea = false;
                        _selectedBasraArea = v;
                      }
                    });
                  },
                ),
                if (_basraUseCustomArea) ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(
                      controller: _basraCustomAreaCtrl,
                      decoration: _dec('اسم المنطقة *')),
                ],
              ] else
                TextField(
                    controller: _areaOtherCtrl,
                    decoration: _dec('المنطقة *')),
              const SizedBox(height: 8),
              TextField(
                controller: _textAddrCtrl,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.next,
                decoration: _dec('عنوان العيادة (نص) *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
                ],
                decoration: _dec('رقم الهاتف *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ph2Ctrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
                ],
                decoration: _dec('الهاتف الثاني (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: _dec('ملاحظات *'),
              ),
              const SizedBox(height: 20),
              addClinicStyleMapLocationBlock(
                latitude: _pickedLatitude,
                longitude: _pickedLongitude,
                onChanged: (double? latitude, double? longitude) {
                  setState(() {
                    _pickedLatitude = latitude;
                    _pickedLongitude = longitude;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saving ? null : _submitForm,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEdit ? 'حفظ التعديل' : 'إضافة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  void _submitForm() {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final String name = _nameCtrl.text.trim();
    final String textAddr = _textAddrCtrl.text.trim();
    final String ph = _phCtrl.text.trim();
    final String notes = _notesCtrl.text.trim();
    final String area = _buildArea();

    final MedicalCategorySelectorState? med =
        _medicalCategoryKey.currentState;

    String? error;
    if (name.length < 2) {
      error = 'أدخل اسم الطبيب أو المركز';
    } else if (med == null || !med.validateSelection()) {
      error = 'اختر المجال الطبي وأكمل التخصص إن وُجد';
    } else if (area.length < 2) {
      error = 'أدخل المنطقة';
    } else if (textAddr.length < 3) {
      error = 'أدخل عنوان العيادة';
    } else if (ph.length < 6) {
      error = 'أدخل رقم الهاتف';
    } else if (notes.length < 3) {
      error = 'أدخل الملاحظات';
    } else if (_pickedLatitude == null || _pickedLongitude == null) {
      error = 'يجب تحديد موقع العيادة على خرائط Google';
    }

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      setState(() => _saving = false);
      return;
    }

    final int? specializationId =
        med!.specializationId ?? _selectedSpecializationId;
    final Map<String, dynamic> row = <String, dynamic>{
      'name': name,
      'spec': med.composeStoredSpec(),
      'gove': _selectedGove,
      'area': area,
      'addr': textAddr,
      'ph': ph,
      'ph2': _ph2Ctrl.text.trim(),
      'notes': 'العنوان: $textAddr\n\nملاحظات: $notes',
      'specialization_id': ?specializationId,
      ...DoctorCoordinates.supabasePair(
        latitude: _pickedLatitude,
        longitude: _pickedLongitude,
      ),
    };
    Navigator.of(context, rootNavigator: true).pop(row);
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}
