// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app_navigation.dart';
import '../../../../core/config/app_endpoints.dart';
import '../../../../data/doctor_coordinates.dart';
import '../../../../edit_suggestion/arabic_column_label.dart';
import '../../../../edit_suggestion/column_edit_semantics.dart';
import '../../../../edit_suggestion/dynamic_report_insert.dart';
import '../../../../edit_suggestion/edit_suggestion_schema_service.dart';
import '../../../../edit_suggestion/schema_models.dart';
import '../../../../location_picker_screen.dart';

/// مطابقة لـ [kInfoCorrectionTypeLabels] في main.dart — لتفادي استيراد main.dart (حلقة اعتماد).
const Map<String, String> _kInfoCorrectionTypeLabels = <String, String>{
  'wrong_phone': 'رقم الهاتف',
  'wrong_address': 'نص العنوان',
  'wrong_map_location': 'موقع العيادة على الخريطة',
  'wrong_name_or_spec': 'الاسم أو التخصص',
  'other': 'معلومة أخرى',
};

/// مطابقة لقيود DB و [main.dart].
const String _kReportStatusPending = 'pending';
const String _kReportStatusResolved = 'resolved';

/// أعمدة doctors المسموح للـ anon بتحديثها — مطابقة لـ [kAdminUpdatableDoctorColumns] في main.
const Set<String> _kAdminUpdatableDoctorColumns = <String>{
  'name',
  'spec',
  'addr',
  'ph',
  'ph2',
  'notes',
  'area',
  'gove',
  'latitude',
  'longitude',
};

/// مراجعة وتطبيق اقتراحات تعديل البيانات من جدول التقارير.
class ReportsManagementScreen extends StatefulWidget {
  const ReportsManagementScreen({super.key});

  @override
  State<ReportsManagementScreen> createState() =>
      _ReportsManagementScreenState();
}

class _ReportsManagementScreenState extends State<ReportsManagementScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EditSuggestionSchemaService _reportSchemaService =
      EditSuggestionSchemaService(Supabase.instance.client);
  EditSuggestionSchemaBundle? _reportSchemaBundle;

  bool _isLoading = true;
  List<Map<String, dynamic>> _reportRows = <Map<String, dynamic>>[];

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final EditSuggestionSchemaBundle schemaBundle =
        await _reportSchemaService.loadBundle();
    List<Map<String, dynamic>> nextReports = <Map<String, dynamic>>[];
    try {
      final String repTable = schemaBundle.ok
          ? schemaBundle.reportsTable
          : AppEndpoints.reports;
      final List<dynamic> reports = await _supabase
          .from(repTable)
          .select()
          .eq('status', _kReportStatusPending)
          .order('created_at', ascending: false)
          .limit(200);
      nextReports = reports.cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        _showSnack('تعذر جلب اقتراحات التعديل: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      _reportRows = nextReports;
      _reportSchemaBundle = schemaBundle;
      _isLoading = false;
    });
  }

  String _adminReportsTable() {
    final EditSuggestionSchemaBundle? b = _reportSchemaBundle;
    if (b != null && b.ok && b.reportsTable.isNotEmpty) {
      return b.reportsTable;
    }
    return AppEndpoints.reports;
  }

  String _adminDoctorsEntityTable() {
    final EditSuggestionTarget? t = _reportSchemaBundle?.primaryTarget;
    if (t != null && t.refTable.isNotEmpty) {
      return t.refTable;
    }
    return AppEndpoints.doctors;
  }

  String _adminReportFkColumn() {
    final String? c = _reportSchemaBundle?.primaryTarget?.fkColumn;
    if (c != null && c.isNotEmpty) {
      return c;
    }
    return 'doctor_id';
  }

  int? _adminReportTargetId(Map<String, dynamic> r) {
    return int.tryParse(
      (r[_adminReportFkColumn()] ?? r['doctor_id'] ?? '').toString(),
    );
  }

  SchemaColumn? _schemaColumnByName(String name) {
    final List<SchemaColumn>? list =
        _reportSchemaBundle?.primaryTarget?.refColumns;
    if (list == null) {
      return null;
    }
    for (final SchemaColumn c in list) {
      if (c.columnName == name) {
        return c;
      }
    }
    return null;
  }

  String _fieldForIssueType(String? type) {
    switch (type) {
      case 'wrong_phone':
        return 'ph';
      case 'wrong_address':
        return 'addr';
      case 'wrong_name_or_spec':
        return 'name';
      default:
        return 'notes';
    }
  }

  Future<void> _syncReportTotal(int docId) async {
    try {
      final String fk = _adminReportFkColumn();
      final List<dynamic> pending = await _supabase
          .from(_adminReportsTable())
          .select('id')
          .eq(fk, docId)
          .eq('status', _kReportStatusPending);
      await _supabase.from(AppEndpoints.doctorReportTotals).upsert(
        <String, dynamic>{
          'doctor_id': docId,
          'report_count': pending.length,
        },
        onConflict: 'doctor_id',
      );
    } catch (e) {
      debugPrint('_syncReportTotal failed for docId=$docId: $e');
    }
  }

  Future<void> _deleteReport(Map<String, dynamic> r) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('تأكيد حذف الاقتراح'),
        content: const Text(
          'هل تريد حذف هذا الاقتراح نهائياً؟ لا يمكن التراجع.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final int? docId = _adminReportTargetId(r);
    try {
      final List<dynamic> deleted = await _supabase
          .from(_adminReportsTable())
          .delete()
          .eq('id', r['id'])
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          'لم يُحذف الاقتراح. طبّق ترحيل Supabase الأحديث أو تحقق من JWT للأدمن.',
        );
      }
      if (docId != null) {
        await _syncReportTotal(docId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الاقتراح.')),
      );
      await _loadReports();
    } catch (error) {
      _showSnack('فشل الحذف: $error');
    }
  }

  Future<void> _applyDirectCorrection(Map<String, dynamic> report) async {
    final int? doctorId = _adminReportTargetId(report);
    if (doctorId == null) {
      _showSnack('تعذر تحديد العيادة المستهدفة.');
      return;
    }
    try {
      final double? lat = DoctorCoordinates.readSuggestedLatitude(report);
      final double? lng = DoctorCoordinates.readSuggestedLongitude(report);
      if (lat != null && lng != null) {
        await _supabase.rpc(
          AppEndpoints.adminApplyCoordCorrection,
          params: <String, dynamic>{
            'p_report_id': report['id'],
            'p_doctor_id': doctorId,
            'p_lat': lat,
            'p_lng': lng,
          },
        );
      } else {
        final String field = resolveReportTargetColumn(report) ??
            _fieldForIssueType(report['info_issue_type']?.toString());
        final String newValue =
            (report['suggested_correction'] ?? '').toString().trim();
        await _supabase.rpc(
          AppEndpoints.adminApplyReportCorrection,
          params: <String, dynamic>{
            'p_report_id': report['id'],
            'p_doctor_id': doctorId,
            'p_field_name': field,
            'p_new_value': newValue,
          },
        );
      }
      await _syncReportTotal(doctorId);
      if (!mounted) return;
      _showSnack('تم تطبيق التصحيح بنجاح');
      await _loadReports();
    } catch (error) {
      _showSnack('فشل التطبيق المباشر: $error');
    }
  }

  Future<void> _approveReport(Map<String, dynamic> r) async {
    final int? docId = _adminReportTargetId(r);
    if (docId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تحديد الطبيب المستهدف لهذا الاقتراح.'),
        ),
      );
      return;
    }

    if (r['info_issue_type']?.toString() == 'wrong_map_location') {
      final double? la = DoctorCoordinates.readSuggestedLatitude(r);
      final double? ln = DoctorCoordinates.readSuggestedLongitude(r);
      if (la != null && ln != null) {
        await _commitMapLocationApproval(r, docId, la, ln);
        return;
      }
      await _applyMapFromReport(r, docId);
      return;
    }

    final String? rawField = resolveReportTargetColumn(r);
    final String? field = rawField?.isNotEmpty == true
        ? rawField
        : _fieldForIssueType(r['info_issue_type']?.toString());
    if (field == null || field.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تحديد الحقل المراد تعديله. استخدم «تعديل يدوي».'),
        ),
      );
      return;
    }
    if (!_kAdminUpdatableDoctorColumns.contains(field)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الحقل «$field» غير مسموح بتحديثه من لوحة الأدمن. '
            'استخدم «تعديل يدوي» أو وسّع صلاحيات anon.',
          ),
        ),
      );
      return;
    }
    final String newValue = (r['suggested_correction'] ?? '').toString().trim();
    if (newValue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الاقتراح لا يتضمّن قيمة جديدة. استخدم «تعديل يدوي».'),
        ),
      );
      return;
    }
    await _commitCorrection(r, docId, field, newValue);
  }

  Future<void> _commitMapLocationApproval(
    Map<String, dynamic> r,
    int docId,
    double la,
    double ln,
  ) async {
    try {
      final List<dynamic> doctorUpdated = await _supabase
          .from(_adminDoctorsEntityTable())
          .update(<String, dynamic>{
            'latitude': la,
            'longitude': ln,
          })
          .eq('id', docId)
          .select('id');
      if (doctorUpdated.isEmpty) {
        throw Exception('لم يتم تحديث بيانات الطبيب المستهدف.');
      }
      final List<dynamic> reportUpdated = await _supabase
          .from(_adminReportsTable())
          .update(<String, dynamic>{
            'status': _kReportStatusResolved,
          })
          .eq('id', r['id'])
          .eq('status', _kReportStatusPending)
          .select('id');
      if (reportUpdated.isEmpty) {
        throw Exception(
            'لم تتغير حالة الاقتراح (قد يكون عولج مسبقاً أو لا توجد صلاحية).');
      }
      await _syncReportTotal(docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت الموافقة وتحديث موقع العيادة.'),
        ),
      );
      await _loadReports();
    } catch (error) {
      _showSnack('فشلت الموافقة على الموقع: $error');
    }
  }

  Future<void> _applyMapFromReport(
    Map<String, dynamic> r,
    int docId,
  ) async {
    double initLa = 30.5039;
    double initLo = 47.7806;
    try {
      final List<dynamic> res = await _supabase
          .from(_adminDoctorsEntityTable())
          .select('latitude, longitude')
          .eq('id', docId)
          .limit(1);
      if (res.isNotEmpty) {
        final Map<String, dynamic> d = res.first as Map<String, dynamic>;
        initLa = DoctorCoordinates.readLatitude(d) ?? initLa;
        initLo = DoctorCoordinates.readLongitude(d) ?? initLo;
      }
    } catch (_) {}
    final double? sugLa = DoctorCoordinates.readSuggestedLatitude(r);
    final double? sugLo = DoctorCoordinates.readSuggestedLongitude(r);
    if (sugLa != null && sugLo != null) {
      initLa = sugLa;
      initLo = sugLo;
    }
    if (!mounted) return;
    final LocationPickResult? picked =
        await Navigator.of(context, rootNavigator: true)
            .push<LocationPickResult>(
      buildAdaptiveRtlRoute<LocationPickResult>(
        LocationPickerScreen(
          initialLatitude: initLa,
          initialLongitude: initLo,
          title: 'تأكيد موقع العيادة من الاقتراح',
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    try {
      final List<dynamic> doctorUpdated = await _supabase
          .from(_adminDoctorsEntityTable())
          .update(<String, dynamic>{
            'latitude': picked.latitude,
            'longitude': picked.longitude,
          })
          .eq('id', docId)
          .select('id');
      if (doctorUpdated.isEmpty) {
        throw Exception('لم يتم تحديث بيانات الطبيب المستهدف.');
      }
      final List<dynamic> reportUpdated = await _supabase
          .from(_adminReportsTable())
          .update(<String, dynamic>{
            'status': _kReportStatusResolved,
          })
          .eq('id', r['id'])
          .eq('status', _kReportStatusPending)
          .select('id');
      if (reportUpdated.isEmpty) {
        throw Exception(
            'لم تتغير حالة الاقتراح (قد يكون عولج مسبقاً أو لا توجد صلاحية).');
      }
      await _syncReportTotal(docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث إحداثيات العيادة من الاقتراح.'),
        ),
      );
      await _loadReports();
    } catch (error) {
      _showSnack('فشل تطبيق الموقع: $error');
    }
  }

  Future<void> _applyReportCorrection(Map<String, dynamic> r) async {
    final int? docId = _adminReportTargetId(r);
    if (docId == null) {
      return;
    }

    if (r['info_issue_type']?.toString() == 'wrong_map_location') {
      await _applyMapFromReport(r, docId);
      return;
    }

    Map<String, dynamic>? docRow;
    try {
      final List<SchemaColumn> rc =
          _reportSchemaBundle?.primaryTarget?.refColumns ??
              const <SchemaColumn>[];
      final String selectList = rc.isEmpty
          ? 'id, name, spec, addr, ph, ph2, notes'
          : rc.map((SchemaColumn c) => c.columnName).join(', ');
      final List<dynamic> res = await _supabase
          .from(_adminDoctorsEntityTable())
          .select(selectList)
          .eq('id', docId)
          .limit(1);
      if (res.isNotEmpty) {
        docRow = res.first as Map<String, dynamic>;
      }
    } catch (_) {}

    if (!mounted) return;

    final List<String> fields = _reportSchemaBundle?.primaryTarget == null
        ? <String>['ph', 'ph2', 'addr', 'name', 'spec', 'notes']
        : _reportSchemaBundle!.primaryTarget!.refColumns
            .where(
              (SchemaColumn c) =>
                  !c.isPrimaryKey && !isReporterSkippableColumn(c),
            )
            .map((SchemaColumn c) => c.columnName)
            .toList();
    final Map<String, String> fieldLabels = <String, String>{
      for (final String f in fields)
        f: arabicLabelForColumn(
          _schemaColumnByName(f) ??
              SchemaColumn(
                columnName: f,
                dataType: 'text',
                isNullable: true,
                isPrimaryKey: false,
              ),
        ),
    };

    String selectedField = resolveReportTargetColumn(r) ??
        _fieldForIssueType(r['info_issue_type']?.toString());
    if (fields.isNotEmpty && !fields.contains(selectedField)) {
      selectedField = fields.first;
    }
    if (fields.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد أعمدة قابلة للتعديل في مخطط قاعدة البيانات.'),
          ),
        );
      }
      return;
    }
    final TextEditingController valueCtrl = TextEditingController(
      text: (r['suggested_correction'] ?? '').toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setSt) {
            return AlertDialog(
              title: Text('تطبيق تصحيح — رقم الطبيب: $docId'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (docRow != null) ...<Widget>[
                      const Text(
                        'البيانات الحالية:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الاسم: ${docRow['name']}\n'
                        'التخصص: ${docRow['spec']}\n'
                        'الهاتف: ${docRow['ph']}\n'
                        'العنوان: ${docRow['addr']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'نوع الخطأ: ${_infoTypeLabelAr(r['info_issue_type']?.toString())}',
                    ),
                    const SizedBox(height: 2),
                    Text('موضع الخطأ: ${r['error_location'] ?? ''}'),
                    const SizedBox(height: 2),
                    Text('التصحيح المقترح: ${r['suggested_correction'] ?? ''}'),
                    const SizedBox(height: 12),
                    const Text('الحقل المراد تعديله:'),
                    DropdownButton<String>(
                      value: selectedField,
                      isExpanded: true,
                      items: fields
                          .map(
                            (String f) => DropdownMenuItem<String>(
                              value: f,
                              child: Text(fieldLabels[f] ?? f),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v != null) {
                          setSt(() => selectedField = v);
                        }
                      },
                    ),
                    if (docRow != null)
                      Text(
                        'القيمة الحالية: ${docRow[selectedField] ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: valueCtrl,
                      decoration: const InputDecoration(
                        labelText: 'القيمة الجديدة',
                        filled: true,
                        fillColor: Color(0xFFF2F7FC),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final String newValue = valueCtrl.text.trim();
                    final String field = selectedField;
                    Navigator.of(ctx).pop();
                    await _commitCorrection(r, docId, field, newValue);
                  },
                  child: const Text('تأكيد التعديل'),
                ),
              ],
            );
          },
        );
      },
    );
    valueCtrl.dispose();
  }

  Future<void> _commitCorrection(
    Map<String, dynamic> r,
    int docId,
    String field,
    String newValue,
  ) async {
    try {
      final List<dynamic> doctorUpdated = await _supabase
          .from(_adminDoctorsEntityTable())
          .update(<String, dynamic>{field: newValue})
          .eq('id', docId)
          .select('id');
      if (doctorUpdated.isEmpty) {
        throw Exception('لم يتم تحديث بيانات الطبيب المستهدف.');
      }
      final List<dynamic> reportUpdated = await _supabase
          .from(_adminReportsTable())
          .update(<String, dynamic>{'status': _kReportStatusResolved})
          .eq('id', r['id'])
          .eq('status', _kReportStatusPending)
          .select('id');
      if (reportUpdated.isEmpty) {
        throw Exception(
            'لم تتغير حالة الاقتراح (قد يكون عولج مسبقاً أو لا توجد صلاحية).');
      }
      await _syncReportTotal(docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تطبيق التصحيح وتحديث جدول الأطباء.'),
        ),
      );
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      _showSnack('فشل التطبيق: $error');
    }
  }

  String _infoTypeLabelAr(String? key) {
    if (key == null || key.isEmpty) {
      return '';
    }
    if (key.startsWith('field_edit:')) {
      final String col = key.substring('field_edit:'.length).trim();
      final SchemaColumn? sc = _schemaColumnByName(col);
      if (sc != null) {
        return arabicLabelForColumn(sc);
      }
      return col;
    }
    return _kInfoCorrectionTypeLabels[key] ?? key;
  }

  Widget _buildReportRowCard(Map<String, dynamic> r) {
    final String type = _infoTypeLabelAr(r['info_issue_type']?.toString());
    final String name = (r['doctor_name'] as String?)?.trim() ?? '';
    final String namePart = name.isNotEmpty ? ' — $name' : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            isThreeLine: true,
            leading: Icon(
              type.contains('الهاتف')
                  ? Icons.phone
                  : type.contains('العنوان')
                      ? Icons.place
                      : type.contains('موقع')
                          ? Icons.map_outlined
                          : Icons.person,
              color: const Color(0xFF1D3557),
            ),
            title: Text(
              'id: ${_adminReportTargetId(r) ?? ''}$namePart',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D3557),
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              '$type\n'
              'الخطأ: ${r['error_location']}\n'
              'التصحيح المقترح: ${r['suggested_correction']}',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _applyDirectCorrection(r),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('تطبيق مباشر'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _applyReportCorrection(r),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('تعديل يدوي'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => _deleteReport(r),
              icon: const Icon(Icons.delete_outline, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              label: const Text('حذف'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: _reportRows.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const <Widget>[
                SizedBox(height: 80),
                Center(
                  child: Text(
                    'لا توجد اقتراحات تعديل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF4A5568)),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: _reportRows.map(_buildReportRowCard).toList(),
            ),
    );
  }
}
