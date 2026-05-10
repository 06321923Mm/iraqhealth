// ✅ UPDATED 2026-05-09
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../features/verification/data/repositories/verification_repository.dart';

class VerificationReviewScreen extends StatefulWidget {
  const VerificationReviewScreen({super.key});

  @override
  State<VerificationReviewScreen> createState() => _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  late final VerificationRepository _repo = VerificationRepository(_db);
  bool _loading = true;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<dynamic> res = await _db
          .from(AppEndpoints.verificationRequests)
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = res.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('تعذر تحميل طلبات التوثيق: $e');
    }
  }

  Future<void> _openReviewSheet(Map<String, dynamic> row) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _VerificationDecisionSheet(
        requestRow: row,
        repository: _repo,
        onApproved: (String requestId, int doctorId) async {
          try {
            await _db.rpc(
              AppEndpoints.adminApproveVerification,
              params: <String, dynamic>{
                'p_request_id': requestId,
                'p_doctor_id': doctorId,
              },
            );
            if (!mounted) return;
            setState(() => _rows.removeWhere((Map<String, dynamic> r) => r['id'] == requestId));
            _showSnack('تمت الموافقة على طلب التوثيق.');
          } catch (e) {
            _showSnack('تعذرت الموافقة: $e');
          }
        },
        onRejected: (String requestId, String notes) async {
          try {
            await _db.rpc(
              AppEndpoints.adminRejectVerification,
              params: <String, dynamic>{
                'p_request_id': requestId,
                'p_admin_notes': notes,
              },
            );
            if (!mounted) return;
            setState(() => _rows.removeWhere((Map<String, dynamic> r) => r['id'] == requestId));
            _showSnack('تم رفض طلب التوثيق.');
          } catch (e) {
            _showSnack('تعذر رفض الطلب: $e');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _rows.isEmpty
          ? ListView(
              children: <Widget>[
                const SizedBox(height: 140),
                const Icon(Icons.verified_user, size: 64, color: Color(0xFFCBD5E1)),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'لا توجد طلبات توثيق معلقة',
                    style: GoogleFonts.cairo(fontSize: 15, color: const Color(0xFF94A3B8)),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length,
              itemBuilder: (_, int i) {
                final Map<String, dynamic> row = _rows[i];
                final String id = (row['id'] ?? '').toString();
                final int? doctorId = row['doctor_id'] is int
                    ? row['doctor_id'] as int
                    : int.tryParse((row['doctor_id'] ?? '').toString());
                final String createdAt = (row['created_at'] ?? '').toString();
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.verified_user_outlined, color: Color(0xFF1976D2)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                createdAt,
                                style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE0B2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'قيد المراجعة',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: const Color(0xFFFF9800),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Align(
                              alignment: Alignment.centerRight,
                              child: Chip(
                                label: Text('doctor_id: ${doctorId ?? '—'}'),
                                backgroundColor: const Color(0xFFF1F5F9),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => _openReviewSheet(row),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1976D2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('عرض المستندات والبت بالطلب'),
                            ),
                          ],
                        ),
                      ),
                      if (id.isEmpty) const SizedBox.shrink(),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _VerificationDecisionSheet extends StatefulWidget {
  const _VerificationDecisionSheet({
    required this.requestRow,
    required this.repository,
    required this.onApproved,
    required this.onRejected,
  });

  final Map<String, dynamic> requestRow;
  final VerificationRepository repository;
  final Future<void> Function(String requestId, int doctorId) onApproved;
  final Future<void> Function(String requestId, String notes) onRejected;

  @override
  State<_VerificationDecisionSheet> createState() => _VerificationDecisionSheetState();
}

class _VerificationDecisionSheetState extends State<_VerificationDecisionSheet> {
  bool _loadingUrls = true;
  bool _processing = false;
  final Map<String, String> _urls = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  Future<void> _loadUrls() async {
    setState(() => _loadingUrls = true);
    try {
      for (final String field in <String>[
        'id_card_front_url',
        'id_card_back_url',
        'medical_license_url',
      ]) {
        final String path = (widget.requestRow[field] ?? '').toString();
        if (path.isEmpty) continue;
        final String url = await widget.repository.getSignedUrl(path);
        if (!mounted) return;
        _urls[field] = url;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingUrls = false);
    }
  }

  Future<void> _approve() async {
    if (_processing) return;
    final String requestId = (widget.requestRow['id'] ?? '').toString();
    final int? doctorId = widget.requestRow['doctor_id'] is int
        ? widget.requestRow['doctor_id'] as int
        : int.tryParse((widget.requestRow['doctor_id'] ?? '').toString());
    if (requestId.isEmpty || doctorId == null) return;
    setState(() => _processing = true);
    await widget.onApproved(requestId, doctorId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    if (_processing) return;
    final String requestId = (widget.requestRow['id'] ?? '').toString();
    if (requestId.isEmpty) return;
    final TextEditingController ctrl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: const Text('سبب الرفض'),
        content: TextField(controller: ctrl, maxLines: 3),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد الرفض')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _processing = true);
    await widget.onRejected(requestId, ctrl.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, ScrollController controller) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'مستندات التوثيق',
                style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: _loadingUrls
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(12),
                      children: <Widget>[
                        _doc('وجه الهوية', _urls['id_card_front_url']),
                        const SizedBox(height: 10),
                        _doc('ظهر الهوية', _urls['id_card_back_url']),
                        const SizedBox(height: 10),
                        _doc('إجازة المزاولة', _urls['medical_license_url']),
                        const SizedBox(height: 80),
                      ],
                    ),
            ),
            Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: _processing ? null : _approve,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                      child: const Text('✓ موافقة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing ? null : _reject,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('✗ رفض'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _doc(String title, String? url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: url == null || url.isEmpty
              ? Container(
                  height: 180,
                  color: const Color(0xFFF8FAFC),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined, color: Color(0xFF94A3B8)),
                )
              : Image.network(
                  url,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, Widget child, ImageChunkEvent? progress) =>
                      progress == null
                          ? child
                          : Container(
                              height: 220,
                              color: const Color(0xFFF8FAFC),
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(strokeWidth: 2),
                            ),
                  errorBuilder: (_, _, _) => Container(
                    height: 220,
                    color: const Color(0xFFF8FAFC),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
