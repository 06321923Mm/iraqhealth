// ✅ UPDATED 2026-05-09
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/components/loading_button.dart';
import '../../../../core/components/section_header.dart';
import '../../../../core/config/app_endpoints.dart';
import '../../data/models/verification_request_model.dart';
import '../../data/repositories/verification_repository.dart';

class SubmitVerificationScreen extends StatefulWidget {
  const SubmitVerificationScreen({super.key});

  @override
  State<SubmitVerificationScreen> createState() =>
      _SubmitVerificationScreenState();
}

class _SubmitVerificationScreenState extends State<SubmitVerificationScreen> {
  late final VerificationRepository _repo;
  final ImagePicker _picker = ImagePicker();

  // Picked file data
  Uint8List? _frontBytes;
  Uint8List? _backBytes;
  Uint8List? _licenseBytes;
  String _frontExt = 'jpg';
  String _backExt  = 'jpg';
  String _licenseExt = 'jpg';

  // Upload progress
  bool _uploadingFront   = false;
  bool _uploadingBack    = false;
  bool _uploadingLicense = false;
  bool _submitting       = false;

  // Existing request (if any)
  VerificationRequestModel? _existingRequest;
  bool _loadingStatus = true;
  int? _doctorId;

  @override
  void initState() {
    super.initState();
    _repo = VerificationRepository(Supabase.instance.client);
    _loadDoctorId();
    _loadExistingRequest();
  }

  Future<void> _loadDoctorId() async {
    try {
      final int? id = await _repo.fetchDoctorIdForCurrentUser();
      if (!mounted) return;
      setState(() => _doctorId = id);
    } catch (_) {}
  }

  Future<void> _loadExistingRequest() async {
    final String? uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loadingStatus = false);
      return;
    }
    try {
      final int? doctorId = await _repo.fetchDoctorIdForCurrentUser();
      if (!mounted) return;
      _doctorId = doctorId;
      if (doctorId == null) {
        setState(() {
          _existingRequest = null;
          _loadingStatus = false;
        });
        return;
      }
      final List<dynamic> rows = await Supabase.instance.client
          .from(AppEndpoints.verificationRequests)
          .select()
          .eq('doctor_id', doctorId)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _existingRequest = rows.isEmpty
            ? null
            : VerificationRequestModel.fromJson(
                rows.first as Map<String, dynamic>);
        _loadingStatus = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _pickImage(_DocField field) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;

    final Uint8List bytes = await file.readAsBytes();
    final String ext = _safeExt(file.name);
    setState(() {
      switch (field) {
        case _DocField.front:
          _frontBytes = bytes;
          _frontExt   = ext;
        case _DocField.back:
          _backBytes = bytes;
          _backExt   = ext;
        case _DocField.license:
          _licenseBytes = bytes;
          _licenseExt   = ext;
      }
    });
  }

  String _safeExt(String name) {
    final String raw = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : 'jpg';
    return RegExp(r'^[a-z0-9]+$').hasMatch(raw) ? raw : 'jpg';
  }

  String _mimeType(String ext) => switch (ext) {
        'png'  => 'image/png',
        'webp' => 'image/webp',
        _      => 'image/jpeg',
      };

  Future<void> _submit() async {
    final String? uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (_doctorId == null) {
      _snack('لم يتم ربط حسابك بعيادة بعد، يرجى ربط حسابك أولاً.');
      return;
    }

    if (_frontBytes == null || _backBytes == null || _licenseBytes == null) {
      _snack('يرجى رفع جميع المستندات الثلاثة قبل الإرسال.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload front
      setState(() => _uploadingFront = true);
      final String frontPath = '$uid/id_front_$ts.$_frontExt';
      await _repo.uploadDocument(
        bytes: _frontBytes!,
        bucketPath: frontPath,
        contentType: _mimeType(_frontExt),
      );
      setState(() => _uploadingFront = false);

      // Upload back
      setState(() => _uploadingBack = true);
      final String backPath = '$uid/id_back_$ts.$_backExt';
      await _repo.uploadDocument(
        bytes: _backBytes!,
        bucketPath: backPath,
        contentType: _mimeType(_backExt),
      );
      setState(() => _uploadingBack = false);

      // Upload license
      setState(() => _uploadingLicense = true);
      final String licensePath = '$uid/license_$ts.$_licenseExt';
      await _repo.uploadDocument(
        bytes: _licenseBytes!,
        bucketPath: licensePath,
        contentType: _mimeType(_licenseExt),
      );
      setState(() => _uploadingLicense = false);

      // Submit request
      await _repo.submitVerificationRequest(
        doctorId:            _doctorId!,
        idCardFrontPath:     frontPath,
        idCardBackPath:      backPath,
        medicalLicensePath:  licensePath,
      );

      if (!mounted) return;
      _snack('تم إرسال طلب التوثيق بنجاح!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingFront   = false;
        _uploadingBack    = false;
        _uploadingLicense = false;
        _submitting       = false;
      });
      _snack('حدث خطأ أثناء الإرسال: ${e.toString()}');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: AppBar(
          backgroundColor: const Color(0xFF42A5F5),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            'توثيق الحساب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
        ),
        body: _loadingStatus
            ? const Center(child: CircularProgressIndicator())
            : _existingRequest != null
                ? _buildExistingStatus()
                : _buildForm(),
      ),
    );
  }

  Widget _buildExistingStatus() {
    final VerificationRequestModel req = _existingRequest!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _statusIcon(req.status),
            const SizedBox(height: 20),
            Text(
              _statusTitle(req.status),
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1D3557),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusBody(req),
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: const Color(0xFF607D8B),
                height: 1.6,
              ),
            ),
            if (req.status == VerificationStatus.rejected) ...<Widget>[
              const SizedBox(height: 24),
              LoadingButton(
                label: 'إعادة الإرسال',
                icon: Icons.refresh,
                onPressed: () => setState(() {
                  _existingRequest = null;
                  _frontBytes = null;
                  _backBytes  = null;
                  _licenseBytes = null;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(VerificationStatus status) {
    final (Color bg, Color fg, IconData icon) = switch (status) {
      VerificationStatus.pending  => (const Color(0xFFFFF8E1), const Color(0xFFF9A825), Icons.hourglass_top_rounded),
      VerificationStatus.approved => (const Color(0xFFE8F5E9), const Color(0xFF388E3C), Icons.verified_rounded),
      VerificationStatus.rejected => (const Color(0xFFFFEBEE), const Color(0xFFC62828), Icons.cancel_outlined),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 48, color: fg),
    );
  }

  String _statusTitle(VerificationStatus s) => switch (s) {
        VerificationStatus.pending  => 'طلبك قيد المراجعة',
        VerificationStatus.approved => 'تم توثيق حسابك',
        VerificationStatus.rejected => 'تم رفض الطلب',
      };

  String _statusBody(VerificationRequestModel req) {
    final String date =
        '${req.createdAt.day}/${req.createdAt.month}/${req.createdAt.year}';
    return switch (req.status) {
      VerificationStatus.pending  =>
          'تم استلام طلبك بتاريخ $date\nسيتم مراجعته من قِبَل الإدارة قريباً.',
      VerificationStatus.approved =>
          'تهانينا! تم توثيق حسابك ويمكنك الآن إدارة عيادتك بالكامل.',
      VerificationStatus.rejected =>
          'سبب الرفض:\n${req.adminNotes?.isNotEmpty == true ? req.adminNotes! : "لم يُحدَّد سبب."}\n\nيمكنك إعادة الإرسال مع مستندات صحيحة.',
    };
  }

  Widget _buildForm() {
    final bool canSubmit =
        _frontBytes != null && _backBytes != null && _licenseBytes != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildInfoBanner(),
        const SizedBox(height: 16),
        const SectionHeader(
          title: 'المستندات المطلوبة',
          subtitle: 'يجب رفع الصور الثلاث للمتابعة',
        ),
        const SizedBox(height: 8),
        _buildDocField(
          field: _DocField.front,
          label: 'صورة الهوية (الوجه الأمامي)',
          icon: Icons.credit_card,
          bytes: _frontBytes,
          uploading: _uploadingFront,
        ),
        const SizedBox(height: 8),
        _buildDocField(
          field: _DocField.back,
          label: 'صورة الهوية (الوجه الخلفي)',
          icon: Icons.credit_card_outlined,
          bytes: _backBytes,
          uploading: _uploadingBack,
        ),
        const SizedBox(height: 8),
        _buildDocField(
          field: _DocField.license,
          label: 'إجازة مزاولة المهنة',
          icon: Icons.badge_outlined,
          bytes: _licenseBytes,
          uploading: _uploadingLicense,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_submitting || !canSubmit) ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'إرسال طلب التوثيق',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ستُراجَع مستنداتك من قِبَل الإدارة خلال 24 ساعة. '
              'تأكد أن الصور واضحة وغير منتهية الصلاحية.',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: const Color(0xFF1565C0),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocField({
    required _DocField field,
    required String label,
    required IconData icon,
    required Uint8List? bytes,
    required bool uploading,
  }) {
    final bool picked = bytes != null;
    return GestureDetector(
      onTap: uploading || _submitting ? null : () => _pickImage(field),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              label,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: const Color(0xFF1D3557),
              ),
            ),
            const SizedBox(height: 10),
            if (!picked)
              CustomPaint(
                painter: _DashedBorderPainter(),
                child: Container(
                  height: 120,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, color: const Color(0xFF90A4AE)),
                      const SizedBox(height: 8),
                      Text(
                        'اضغط لاختيار صورة',
                        style: GoogleFonts.cairo(
                          color: const Color(0xFF90A4AE),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      bytes,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: Color(0xFF2E7D32),
                      child: Icon(Icons.check, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            if (uploading) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(
                color: Color(0xFF42A5F5),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

enum _DocField { front, back, license }

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double dash = 6;
    const double gap = 4;
    final RRect r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    final Path path = Path()..addRRect(r);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
