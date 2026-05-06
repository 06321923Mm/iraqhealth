import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../features/verification/data/models/verification_request_model.dart';

class VerificationReviewScreen extends StatefulWidget {
  const VerificationReviewScreen({super.key});

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
  final SupabaseClient _db = Supabase.instance.client;

  VerificationStatus _filterStatus = VerificationStatus.pending;
  List<Map<String, dynamic>> _requests = <Map<String, dynamic>>[];
  bool _loading = true;
  Map<String, dynamic>? _selected;

  // Signed URLs cache
  final Map<String, String> _signedUrls = <String, String>{};
  bool _loadingUrls = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() { _loading = true; _selected = null; });
    try {
      final List<dynamic> rows = await _db
          .from(AppEndpoints.verificationRequests)
          .select('*, doctors!inner(name, spec, gove, ph)')
          .eq('status', _filterStatus.value)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _requests = rows.cast<Map<String, dynamic>>();
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectRequest(Map<String, dynamic> req) async {
    setState(() { _selected = req; _loadingUrls = true; _signedUrls.clear(); });
    final String? uid = req['doctor_id'] as String?;
    if (uid == null) { setState(() => _loadingUrls = false); return; }

    for (final String field in <String>['id_card_front_url', 'id_card_back_url', 'medical_license_url']) {
      final String? path = req[field] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final String url = await _db.storage
              .from(AppEndpoints.verificationDocs)
              .createSignedUrl(path, 3600);
          if (mounted) setState(() => _signedUrls[field] = url);
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _loadingUrls = false);
  }

  Future<void> _approve(String requestId, String doctorId) async {
    try {
      await _db.from(AppEndpoints.verificationRequests).update(<String, dynamic>{
        'status': 'approved',
      }).eq('id', requestId);

      _db.functions.invoke(
        'send-notification',
        body: <String, dynamic>{
          'user_id': doctorId,
          'title':   'تم قبول طلب التوثيق',
          'body':    'تهانينا! تم توثيق حسابك ويمكنك الآن إدارة عيادتك بالكامل.',
          'data':    <String, String>{'type': 'verification_approved'},
        },
      ).ignore();

      _snack('تمت الموافقة على الطلب.');
      _loadRequests();
    } catch (e) {
      _snack('خطأ: ${e.toString()}');
    }
  }

  Future<void> _reject(String requestId) async {
    final TextEditingController notesCtrl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('رفض الطلب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: notesCtrl,
            textDirection: TextDirection.rtl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'سبب الرفض (يظهر للطبيب)...',
              hintStyle: GoogleFonts.cairo(color: const Color(0xFFB0BEC5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: GoogleFonts.cairo(),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
    // Read text BEFORE dispose to avoid use-after-free.
    final String adminNotes = notesCtrl.text.trim();
    notesCtrl.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await _db.from(AppEndpoints.verificationRequests).update(<String, dynamic>{
        'status':      'rejected',
        'admin_notes': adminNotes,
      }).eq('id', requestId);

      final String? doctorId = _selected?['doctor_id'] as String?;
      if (doctorId != null) {
        final String notesSuffix = adminNotes.isNotEmpty ? '\nالسبب: $adminNotes' : '';
        _db.functions.invoke(
          'send-notification',
          body: <String, dynamic>{
            'user_id': doctorId,
            'title':   'بشأن طلب التوثيق',
            'body':    'نأسف، لم يتم قبول طلب التوثيق الخاص بك.$notesSuffix',
            'data':    <String, String>{'type': 'verification_rejected'},
          },
        ).ignore();
      }

      _snack('تم رفض الطلب.');
      _loadRequests();
    } catch (e) {
      _snack('خطأ: ${e.toString()}');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.of(context).size.width >= 700;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFilterTabs(),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : wide && _selected != null
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: _buildList()),
                            const SizedBox(width: 16),
                            SizedBox(width: 340, child: _buildReviewPanel()),
                          ],
                        )
                      : _selected != null
                          ? _buildReviewPanel()
                          : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        if (_selected != null)
          IconButton(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          ),
        Expanded(
          child: Text('مراجعة طلبات التوثيق',
              style: GoogleFonts.cairo(
                  fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
        ),
        IconButton(
          onPressed: _loadRequests,
          icon: const Icon(Icons.refresh, color: Color(0xFF42A5F5)),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return Row(
      children: VerificationStatus.values.map((VerificationStatus s) {
        final bool selected = _filterStatus == s;
        final (String label, Color color) = switch (s) {
          VerificationStatus.pending  => ('معلّق', const Color(0xFFF9A825)),
          VerificationStatus.approved => ('مقبول', const Color(0xFF388E3C)),
          VerificationStatus.rejected => ('مرفوض', const Color(0xFFC62828)),
        };
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilterChip(
            label: Text(label, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : color)),
            selected: selected,
            selectedColor: color,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            onSelected: (_) {
              setState(() => _filterStatus = s);
              _loadRequests();
            },
          ),
        );
      }).toList(),
    );
  }

  Widget _buildList() {
    if (_requests.isEmpty) {
      return Center(
        child: Text('لا توجد طلبات في هذه الفئة.',
            style: GoogleFonts.cairo(color: const Color(0xFF90A4AE))),
      );
    }
    return ListView.builder(
      itemCount: _requests.length,
      itemBuilder: (_, int i) {
        final Map<String, dynamic> req = _requests[i];
        final Map<String, dynamic> doctor =
            (req['doctors'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final String doctorName = (doctor['name'] ?? '—').toString();
        final String spec       = (doctor['spec']  ?? '—').toString();
        final String date       = _formatDate(req['created_at'] as String?);
        final bool isSelected   = _selected?['id'] == req['id'];

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: isSelected ? const Color(0xFF42A5F5) : const Color(0xFFE3E8F0)),
          ),
          child: ListTile(
            onTap: () => _selectRequest(req),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.person_outline, color: Color(0xFF42A5F5)),
            ),
            title: Text(doctorName,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text('$spec  •  $date',
                style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF90A4AE))),
            trailing: const Icon(Icons.chevron_left, color: Color(0xFF90A4AE)),
          ),
        );
      },
    );
  }

  Widget _buildReviewPanel() {
    if (_selected == null) return const SizedBox.shrink();
    final Map<String, dynamic> req    = _selected!;
    final Map<String, dynamic> doctor =
        (req['doctors'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String id        = (req['id'] as String?) ?? '';
    final String doctorId  = (req['doctor_id'] as String?) ?? '';
    final String doctorName = (doctor['name'] ?? '—').toString();
    final String spec       = (doctor['spec']  ?? '—').toString();
    final String gove       = (doctor['gove']  ?? '—').toString();
    final String ph         = (doctor['ph']    ?? '—').toString();
    final String date       = _formatDate(req['created_at'] as String?);
    final bool isPending    = (req['status'] as String?) == 'pending';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('معلومات الطبيب',
              style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
          const SizedBox(height: 10),
          _infoRow('الاسم', doctorName),
          _infoRow('التخصص', spec),
          _infoRow('المحافظة', gove),
          _infoRow('الهاتف', ph),
          _infoRow('التاريخ', date),
          const Divider(height: 24),
          Text('المستندات المرفوعة',
              style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
          const SizedBox(height: 10),
          if (_loadingUrls)
            const Center(child: CircularProgressIndicator())
          else ...<Widget>[
            _buildDocImage('صورة الهوية (أمامي)', _signedUrls['id_card_front_url']),
            const SizedBox(height: 10),
            _buildDocImage('صورة الهوية (خلفي)', _signedUrls['id_card_back_url']),
            const SizedBox(height: 10),
            _buildDocImage('إجازة مزاولة المهنة', _signedUrls['medical_license_url']),
          ],
          if (isPending) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(id),
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: Text('رفض', style: GoogleFonts.cairo(color: Colors.red, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _approve(id, doctorId),
                    icon: const Icon(Icons.check),
                    label: Text('موافقة', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF388E3C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocImage(String label, String? url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF607D8B))),
        const SizedBox(height: 4),
        if (url == null || url.isEmpty)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF7FBFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCFD8DC)),
            ),
            child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF90A4AE))),
          )
        else
          GestureDetector(
            onTap: () => _showFullImage(url, label),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                height: 140,
                fit: BoxFit.cover,
                loadingBuilder: (_, Widget child, ImageChunkEvent? progress) =>
                    progress == null
                        ? child
                        : Container(
                            height: 140,
                            color: const Color(0xFFF7FBFF),
                            child: const Center(child: CircularProgressIndicator()),
                          ),
              ),
            ),
          ),
      ],
    );
  }

  void _showFullImage(String url, String title) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 80,
            child: Text(label, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF90A4AE))),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF1D3557), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final DateTime dt = DateTime.tryParse(iso) ?? DateTime.now();
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
