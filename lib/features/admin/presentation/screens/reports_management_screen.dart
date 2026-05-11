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
      // ── Coordinates correction ───────────────────────────────
      final double? lat = DoctorCoordinates.readSuggestedLatitude(report);
      final double? lng = DoctorCoordinates.readSuggestedLongitude(report);

      if (lat != null && lng != null) {
        final List<dynamic> doctorUpdated = await _supabase
            .from(_adminDoctorsEntityTable())
            .update(<String, dynamic>{
              'latitude' : lat,
              'longitude': lng,
            })
            .eq('id', doctorId)
            .select('id');

        if (doctorUpdated.isEmpty) {
          throw Exception(
            'لم يتم تحديث إحداثيات الطبيب. '
            'تحقق من صلاحيات UPDATE على جدول doctors.',
          );
        }
      } else {
        // ── Text field correction ────────────────────────────
        final String field = resolveReportTargetColumn(report) ??
            _fieldForIssueType(report['info_issue_type']?.toString());

        if (field.isEmpty) {
          _showSnack('لا يمكن تحديد الحقل تلقائياً. استخدم «تعديل يدوي».');
          return;
        }

        if (!_kAdminUpdatableDoctorColumns.contains(field)) {
          _showSnack(
            'الحقل «$field» غير مسموح بتحديثه. '
            'استخدم «تعديل يدوي» أو وسّع صلاحيات anon.',
          );
          return;
        }

        final String newValue =
            (report['suggested_correction'] ?? '').toString().trim();

        if (newValue.isEmpty) {
          _showSnack('الاقتراح لا يتضمن قيمة جديدة. استخدم «تعديل يدوي».');
          return;
        }

        final List<dynamic> doctorUpdated = await _supabase
            .from(_adminDoctorsEntityTable())
            .update(<String, dynamic>{field: newValue})
            .eq('id', doctorId)
            .select('id');

        if (doctorUpdated.isEmpty) {
          throw Exception(
            'لم يتم تحديث بيانات الطبيب. '
            'تحقق من صلاحيات UPDATE على جدول doctors.',
          );
        }
      }

      // ── Mark report as resolved ──────────────────────────────
      final List<dynamic> reportUpdated = await _supabase
          .from(_adminReportsTable())
          .update(<String, dynamic>{'status': _kReportStatusResolved})
          .eq('id', report['id'])
          .eq('status', _kReportStatusPending)
          .select('id');

      if (reportUpdated.isEmpty) {
        debugPrint(
          'Warning: report ${report['id']} status not changed '
          '(already resolved or missing permission).',
        );
      }

      await _syncReportTotal(doctorId);

      if (!mounted) return;
      _showSnack('✅ تم تطبيق التصحيح بنجاح.');
      await _loadReports();

    } on PostgrestException catch (e) {
      debugPrint(
          '_applyDirectCorrection PostgrestException: ${e.message} code=${e.code}');
      _showSnack(
        'فشل التطبيق (${e.code}): ${e.message}. '
        'تحقق من صلاحيات UPDATE على جدول doctors.',
      );
    } catch (error) {
      debugPrint('_applyDirectCorrection error: $error');
      _showSnack('فشل التطبيق: $error');
    }
  }

  // Kept for richer approval flow (map + column guards); primary action uses RPC path.
  // ignore: unused_element
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

  Future<void> _showReportDetailSheet(Map<String, dynamic> report) async {
    final int? doctorId = _adminReportTargetId(report);

    Map<String, dynamic>? currentDoctor;
    if (doctorId != null) {
      try {
        final List<dynamic> res = await _supabase
            .from(_adminDoctorsEntityTable())
            .select('id, name, spec, addr, area, ph, ph2, notes, gove')
            .eq('id', doctorId)
            .limit(1);
        if (res.isNotEmpty) {
          currentDoctor = res.first as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('_showReportDetailSheet fetch doctor: $e');
      }
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, ScrollController scrollCtrl) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D3557)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.edit_note_rounded,
                              color: Color(0xFF1D3557),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'تفاصيل اقتراح التعديل',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1D3557),
                                  ),
                                ),
                                if (doctorId != null)
                                  Text(
                                    'رقم الطبيب: $doctorId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(20),
                        children: <Widget>[
                          if (currentDoctor != null) ...<Widget>[
                            _sectionHeader('البيانات الحالية للطبيب',
                                color: const Color(0xFF1976D2)),
                            _detailTable(<Map<String, String>>[
                              <String, String>{
                                'label': 'الاسم',
                                'value': (currentDoctor['name'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'التخصص',
                                'value': (currentDoctor['spec'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'المحافظة',
                                'value': (currentDoctor['gove'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'المنطقة',
                                'value': (currentDoctor['area'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'العنوان',
                                'value': (currentDoctor['addr'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'الهاتف 1',
                                'value': (currentDoctor['ph'] ?? '—')
                                    .toString(),
                              },
                              <String, String>{
                                'label': 'الهاتف 2',
                                'value': (currentDoctor['ph2'] ?? '—')
                                    .toString(),
                              },
                            ]),
                            const SizedBox(height: 16),
                          ],
                          _sectionHeader('تفاصيل الاقتراح المُرسَل',
                              color: const Color(0xFFE65100)),
                          _detailTable(<Map<String, String>>[
                            <String, String>{
                              'label': 'نوع الخطأ',
                              'value': _infoTypeLabelAr(
                                  report['info_issue_type']?.toString()),
                            },
                            <String, String>{
                              'label': 'موضع الخطأ',
                              'value': (report['error_location'] ?? '—')
                                  .toString(),
                            },
                            <String, String>{
                              'label': 'التصحيح المقترح',
                              'value':
                                  (report['suggested_correction'] ?? '—')
                                      .toString(),
                              'highlight': 'true',
                            },
                            if (report['field_name'] != null)
                              <String, String>{
                                'label': 'الحقل المستهدف',
                                'value': report['field_name'].toString(),
                              },
                            <String, String>{
                              'label': 'تاريخ الاقتراح',
                              'value': _formatDate(
                                  report['created_at']?.toString()),
                            },
                          ]),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _applyDirectCorrection(report);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('تطبيق مباشر'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _applyReportCorrection(report);
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            icon: const Icon(Icons.tune),
                            label: const Text('تعديل يدوي'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _deleteReport(report);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('حذف الاقتراح'),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title,
      {Color color = const Color(0xFF1D3557)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTable(List<Map<String, String>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: rows.asMap().entries.map(
          (MapEntry<int, Map<String, String>> entry) {
            final bool isLast = entry.key == rows.length - 1;
            final bool highlight = entry.value['highlight'] == 'true';
            return Container(
              decoration: BoxDecoration(
                color: highlight
                    ? const Color(0xFFFFF3E0)
                    : Colors.transparent,
                borderRadius: isLast
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(12))
                    : null,
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 90,
                          child: Text(
                            entry.value['label'] ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value['value'] ?? '—',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: highlight
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: highlight
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                ],
              ),
            );
          },
        ).toList(),
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final DateTime dt = DateTime.parse(raw).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  Widget _buildReportRowCard(Map<String, dynamic> r) {
    final String type =
        _infoTypeLabelAr(r['info_issue_type']?.toString());
    final String name = (r['doctor_name'] as String?)?.trim() ?? '';
    final String correction =
        (r['suggested_correction'] ?? '').toString().trim();
    final String doctorIdStr =
        (_adminReportTargetId(r) ?? '—').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showReportDetailSheet(r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── Card header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D3557).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      type.contains('الهاتف')
                          ? Icons.phone_outlined
                          : type.contains('العنوان')
                              ? Icons.place_outlined
                              : type.contains('موقع')
                                  ? Icons.map_outlined
                                  : type.contains('الاسم')
                                      ? Icons.person_outline
                                      : Icons.edit_note_rounded,
                      color: const Color(0xFF1D3557),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              'طبيب #$doctorIdStr',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1D3557),
                                fontSize: 13,
                              ),
                            ),
                            if (name.isNotEmpty) ...<Widget>[
                              const Text(
                                ' — ',
                                style: TextStyle(color: Color(0xFF94A3B8)),
                              ),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1D3557),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            type,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1565C0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_left_rounded,
                    color: Color(0xFFCBD5E1),
                    size: 20,
                  ),
                ],
              ),
            ),
            // ── Suggested correction preview ───────────────────
            if (correction.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.lightbulb_outline_rounded,
                        size: 14, color: Color(0xFFE65100)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        correction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            // ── Action buttons ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _applyDirectCorrection(r),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.check_circle_outline,
                          size: 16),
                      label: const Text('تطبيق',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _applyReportCorrection(r),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('يدوي',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => _deleteReport(r),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red, size: 20),
                    tooltip: 'حذف',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
