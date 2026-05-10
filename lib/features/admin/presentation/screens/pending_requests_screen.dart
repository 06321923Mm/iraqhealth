// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../data/doctor_coordinates.dart';

enum _DuplicateApprovalChoice { cancel, deleteRequest, updateExisting }

/// طلبات إضافة العيادات المعلّقة وطلبات استحواذ العيادات.
class PendingRequestsScreen extends StatefulWidget {
  const PendingRequestsScreen({super.key});

  @override
  State<PendingRequestsScreen> createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingDoctors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _clinicClaimRequests = <Map<String, dynamic>>[];

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> nextPending = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> nextClinicClaims = <Map<String, dynamic>>[];
    try {
      final List<dynamic> pending = await _supabase
          .from(AppEndpoints.pendingDoctors)
          .select()
          .order('id');
      nextPending = pending.cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        _showSnack('تعذر جلب طلبات العيادات: $error');
      }
    }
    try {
      final List<dynamic> claims = await _supabase
          .from(AppEndpoints.clinicClaimRequests)
          .select('id, doctor_id, user_id, clinic_name, status, created_at')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(200);
      nextClinicClaims = claims.cast<Map<String, dynamic>>();
    } catch (error) {
      if (mounted) {
        _showSnack('تعذر جلب طلبات استحواذ العيادات: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      _pendingDoctors = nextPending;
      _clinicClaimRequests = nextClinicClaims;
      _isLoading = false;
    });
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    const List<String> kDoctorCols = <String>[
      'name',
      'spec',
      'addr',
      'area',
      'ph',
      'notes',
      'gove',
    ];
    final Map<String, dynamic> payload = <String, dynamic>{
      for (final String k in kDoctorCols) k: request[k],
      'ph2': (request['ph2'] ?? '').toString(),
    };
    final double? reqLat = DoctorCoordinates.readLatitude(request);
    final double? reqLng = DoctorCoordinates.readLongitude(request);
    if (reqLat == null || reqLng == null) {
      if (mounted) {
          _showSnack(
            'لا يمكن الموافقة: الطلب يجب أن يتضمّن موقعاً محدداً على الخريطة.',
          );
      }
      return;
    }
    payload['latitude'] = reqLat;
    payload['longitude'] = reqLng;
    final String addrVal = (payload['addr'] ?? '').toString().trim();
    if (addrVal.startsWith('http://') || addrVal.startsWith('https://')) {
      payload['addr'] = '—';
    }

    final String reqName = (request['name'] ?? '').toString().trim();
    final String reqGove = (request['gove'] ?? '').toString().trim();
    final String reqPh   = (request['ph']   ?? '').toString().trim();

    // Smart duplicate detection: name similarity > 0.8, same gove, optional phone overlap.
    List<Map<String, dynamic>> candidates = const <Map<String, dynamic>>[];
    try {
      final dynamic res = await _supabase.rpc(
        AppEndpoints.findDuplicateDoctor,
        params: <String, dynamic>{
          'p_name':      reqName,
          'p_gove':      reqGove,
          'p_phone':     reqPh,
          'p_threshold': 0.8,
        },
      );
      if (res is List) {
        candidates = res.cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // Fall back to legacy exact-match guard if RPC isn't deployed yet.
      try {
        final List<dynamic> existing = await _supabase
            .from(AppEndpoints.doctors)
            .select('id, name, spec, gove, ph, ph2')
            .eq('name', reqName)
            .eq('gove', reqGove)
            .limit(1);
        candidates = existing.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    if (candidates.isNotEmpty) {
      final Map<String, dynamic> top = candidates.first;
      final _DuplicateApprovalChoice? choice =
          await _askSmartDuplicateApprovalChoice(reqName, candidates);
      if (choice == null || choice == _DuplicateApprovalChoice.cancel) {
        return;
      }
      if (choice == _DuplicateApprovalChoice.deleteRequest) {
        await _rejectRequest(request);
        return;
      }
      if (choice == _DuplicateApprovalChoice.updateExisting) {
        try {
          await _supabase
              .from(AppEndpoints.doctors)
              .update(payload)
              .eq('id', top['id']);
          final bool removed =
              await _deletePendingDoctorRow(request['id']);
          if (!removed) {
            throw Exception('لم يُحذف طلب الانتظار بعد التحديث.');
          }
          if (!mounted) return;
          _showSnack('تم تحديث بيانات العيادة الموجودة من بيانات الطلب.');
          await _load();
        } catch (error) {
          if (!mounted) return;
          _showSnack('فشل تحديث العيادة: $error');
        }
        return;
      }
    }

    try {
      await _supabase.from(AppEndpoints.doctors).insert(payload);
      final bool removed = await _deletePendingDoctorRow(request['id']);
      if (!removed) {
        throw Exception('لم يُحذف طلب الانتظار بعد إضافة العيادة.');
      }
      if (!mounted) return;
      _showSnack('تمت الموافقة وإضافة العيادة إلى القائمة.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_humanReadableApprovalError(error));
    }
  }

  Future<_DuplicateApprovalChoice?> _askSmartDuplicateApprovalChoice(
    String requestedName,
    List<Map<String, dynamic>> candidates,
  ) {
    return showDialog<_DuplicateApprovalChoice>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('عيادات مشابهة قائمة'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'الطلب: «$requestedName». تم العثور على ${candidates.length} '
                  'عيادة محتملة التطابق.',
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (BuildContext context, int _) =>
                        const Divider(height: 8),
                    itemBuilder: (BuildContext _, int i) {
                      final Map<String, dynamic> c = candidates[i];
                      final dynamic rawScore = c['similarity_score'];
                      final double score =
                          rawScore is num ? rawScore.toDouble() : 0;
                      final bool phoneMatch = c['phone_match'] == true;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (c['name'] ?? '').toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          'تخصص: ${(c['spec'] ?? '').toString()}\n'
                          'تشابه الاسم: ${(score * 100).toStringAsFixed(0)}%'
                          '${phoneMatch ? ' • تطابق هاتف' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_DuplicateApprovalChoice.cancel),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(_DuplicateApprovalChoice.deleteRequest),
              child: const Text('حذف الطلب فقط'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(_DuplicateApprovalChoice.updateExisting),
              child: const Text('تحديث أعلى تطابق'),
            ),
          ],
        );
      },
    );
  }

  String _humanReadableApprovalError(Object error) {
    final String text = error.toString();
    if (text.contains('doctors_unique') ||
        text.contains('duplicate key') ||
        text.contains('23505')) {
      return 'العيادة موجودة مسبقاً (نفس الاسم/الاختصاص/المحافظة). جرّب «تحديث الموجودة» أو «حذف الطلب».';
    }
    if (text.contains('row-level security') ||
        text.contains('permission denied')) {
      return 'لا توجد صلاحيات كافية على قاعدة البيانات لإتمام الموافقة.';
    }
    return 'فشلت الموافقة: $error';
  }

  Future<bool> _deletePendingDoctorRow(Object? id) async {
    if (id == null) {
      return false;
    }
    final List<dynamic> deleted = await _supabase
        .from(AppEndpoints.pendingDoctors)
        .delete()
        .eq('id', id)
        .select('id');
    return deleted.isNotEmpty;
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    try {
      final bool removed = await _deletePendingDoctorRow(request['id']);
      if (!removed) {
        throw Exception(
          'لم يُحذف الطلب. طبّق ترحيل Supabase «fix_admin_trigger_delete» أو تحقق من صلاحية admin في JWT.',
        );
      }
      if (!mounted) return;
      _showSnack('تم رفض الطلب وحذفه من الانتظار.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('تعذر الحذف: $error');
    }
  }

  Future<void> _approveClinicClaim(Map<String, dynamic> row) async {
    try {
      final List<dynamic> updated = await _supabase
          .from(AppEndpoints.clinicClaimRequests)
          .update(<String, dynamic>{'status': 'approved'})
          .eq('id', row['id'])
          .eq('status', 'pending')
          .select('id, status');
      if (updated.isEmpty) {
        throw Exception('تعذرت الموافقة: الطلب غير موجود أو عولج مسبقاً.');
      }
      if (!mounted) return;
      _showSnack('تمت الموافقة على الطلب وربط العيادة.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('فشلت الموافقة على طلب الاستحواذ: $error');
    }
  }

  Future<void> _rejectClinicClaim(Map<String, dynamic> row) async {
    try {
      final List<dynamic> updated = await _supabase
          .from(AppEndpoints.clinicClaimRequests)
          .update(<String, dynamic>{'status': 'rejected'})
          .eq('id', row['id'])
          .eq('status', 'pending')
          .select('id, status');
      if (updated.isEmpty) {
        throw Exception('تعذر الرفض: الطلب غير موجود أو عولج مسبقاً.');
      }
      if (!mounted) return;
      _showSnack('تم رفض طلب الاستحواذ.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showSnack('فشل رفض طلب الاستحواذ: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final bool emptyClaims = _clinicClaimRequests.isEmpty;
    final bool emptyPending = _pendingDoctors.isEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: emptyClaims && emptyPending
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const <Widget>[
                SizedBox(height: 80),
                Center(
                  child: Text(
                    'لا توجد طلبات بانتظار المراجعة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF4A5568)),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                if (!emptyClaims) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                    child: Text(
                      'طلبات استحواذ العيادات',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D3557),
                      ),
                    ),
                  ),
                  ..._clinicClaimRequests.map(
                    (Map<String, dynamic> item) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ListTile(
                              title: Text(
                                (item['clinic_name'] ?? '—').toString(),
                              ),
                              subtitle: Text(
                                'doctor_id: ${(item['doctor_id'] ?? '').toString()}\n'
                                'user_id: ${(item['user_id'] ?? '').toString()}\n'
                                'التاريخ: ${(item['created_at'] ?? '').toString()}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 8, right: 8, bottom: 8),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () =>
                                          _approveClinicClaim(item),
                                      child: const Text('موافقة وربط'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          _rejectClinicClaim(item),
                                      child: const Text('رفض'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 28),
                ],
                if (!emptyPending)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      'طلبات إضافة عيادات',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D3557),
                      ),
                    ),
                  ),
                ..._pendingDoctors.map((Map<String, dynamic> item) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFE3F2FD),
                              child: Icon(
                                Icons.local_hospital_outlined,
                                color: Color(0xFF42A5F5),
                              ),
                            ),
                            title:
                                Text((item['name'] ?? 'بدون اسم').toString(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1D3557),
                                    )),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF607D8B)),
                                    const SizedBox(width: 4),
                                    Text((item['spec'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B))),
                                  ],
                                ),
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.place_outlined, size: 14, color: Color(0xFF607D8B)),
                                    const SizedBox(width: 4),
                                    Text((item['area'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B))),
                                  ],
                                ),
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.location_city_outlined, size: 14, color: Color(0xFF607D8B)),
                                    const SizedBox(width: 4),
                                    Text((item['gove'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B))),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 8, right: 8, bottom: 8),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _approveRequest(item),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('موافق (إضافة)'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _rejectRequest(item),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('غير موافق (حذف)'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
