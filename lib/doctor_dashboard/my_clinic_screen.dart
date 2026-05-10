// ✅ UPDATED 2026-05-09
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../core/components/loading_button.dart';
import '../core/components/status_badge.dart';
import '../core/config/app_endpoints.dart';
import '../core/services/image_processing_service.dart';
import '../doctor_constants.dart';
import '../features/my_clinic/presentation/widgets/quick_status_widget.dart';
import '../features/verification/data/models/verification_request_model.dart';
import '../features/verification/presentation/screens/submit_verification_screen.dart';
import '../widgets/doctor_map_location_field.dart';
import '../widgets/medical_category_selector.dart';

enum _ViewMode {
  checking,
  unclaimed,
  claimPending,
  verificationNotStarted,
  verificationPending,
  verificationRejected,
  editing,
}

class MyClinicScreen extends StatefulWidget {
  const MyClinicScreen({super.key});

  @override
  State<MyClinicScreen> createState() => _MyClinicScreenState();
}

class _MyClinicScreenState extends State<MyClinicScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  _ViewMode _mode = _ViewMode.checking;

  // Clinic data
  Map<String, dynamic>? _clinicRaw;

  // Claim request data
  String? _pendingRequestId;
  String? _pendingClinicName;
  DateTime? _pendingCreatedAt;

  // Verification request data
  VerificationRequestModel? _verificationRequest;

  // Search state
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;

  final GlobalKey<MedicalCategorySelectorState> _medicalCategoryKey =
      GlobalKey<MedicalCategorySelectorState>();

  // Edit form state
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl    = TextEditingController();
  final TextEditingController _addrCtrl    = TextEditingController();
  final TextEditingController _ph1Ctrl     = TextEditingController();
  final TextEditingController _ph2Ctrl     = TextEditingController();
  final TextEditingController _notesCtrl   = TextEditingController();
  final TextEditingController _areaCtrl    = TextEditingController();
  final TextEditingController _profileImageCtrl = TextEditingController();
  String? _profileBlurhash;
  final ImagePicker _imagePicker = ImagePicker();
  String _loadedDoctorSpecForMedicalUi = '';
  String? _selectedGove;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  bool _uploadingProfileImage = false;
  bool _saveSuccess = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadMyClinic();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _ph1Ctrl.dispose();
    _ph2Ctrl.dispose();
    _notesCtrl.dispose();
    _areaCtrl.dispose();
    _profileImageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyClinic() async {
    final String? uid = _db.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _mode = _ViewMode.unclaimed);
      return;
    }
    setState(() => _mode = _ViewMode.checking);
    try {
      // 1. Is a clinic already linked?
      final List<dynamic> owned = await _db
          .from(AppEndpoints.doctors)
          .select(
              'id, spec, name, addr, area, ph, ph2, notes, gove, latitude, longitude, '
              'profile_image_url, image_blurhash, owner_user_id, is_verified, '
              'verification_date, current_status, '
              'status_message, status_expires_at')
          .eq('owner_user_id', uid)
          .limit(1);
      if (!mounted) return;

      if (owned.isNotEmpty) {
        final Map<String, dynamic> raw = owned.first as Map<String, dynamic>;
        _populateForm(raw);
        final bool isVerified = (raw['is_verified'] as bool?) ?? false;

        if (isVerified) {
          setState(() {
            _clinicRaw = raw;
            _mode = _ViewMode.editing;
          });
          return;
        }

        // Clinic linked but not verified — check verification request
        List<dynamic> vReqs = <dynamic>[];
        try {
          final dynamic doctorPk = raw['id'];
          vReqs = await _db
              .from(AppEndpoints.verificationRequests)
              .select()
              .eq('doctor_id', doctorPk)
              .order('created_at', ascending: false)
              .limit(1);
        } catch (_) {
          // شبكة أو إعداد RLS؛ نُعامل كعدم وصول للنتيجة دون إسقاط المستخدم إلى «غير مرتبط»
        }
        if (!mounted) return;

        if (vReqs.isEmpty) {
          setState(() {
            _clinicRaw = raw;
            _mode = _ViewMode.verificationNotStarted;
          });
          return;
        }

        final VerificationRequestModel vReq = VerificationRequestModel.fromJson(
            vReqs.first as Map<String, dynamic>);

        setState(() {
          _clinicRaw = raw;
          _verificationRequest = vReq;
          _mode = vReq.status == VerificationStatus.rejected
              ? _ViewMode.verificationRejected
              : _ViewMode.verificationPending;
        });
        return;
      }

      // 2. Any pending claim request?
      final List<dynamic> pending = await _db
          .from(AppEndpoints.clinicClaimRequests)
          .select('id, clinic_name, created_at')
          .eq('user_id', uid)
          .eq('status', 'pending')
          .limit(1);
      if (!mounted) return;

      if (pending.isNotEmpty) {
        final Map<String, dynamic> req = pending.first as Map<String, dynamic>;
        setState(() {
          _pendingRequestId   = req['id'] as String?;
          _pendingClinicName  = (req['clinic_name'] ?? '').toString();
          _pendingCreatedAt   = req['created_at'] != null
              ? DateTime.tryParse(req['created_at'].toString())
              : null;
          _mode = _ViewMode.claimPending;
        });
        return;
      }

      setState(() => _mode = _ViewMode.unclaimed);
    } catch (_) {
      if (mounted) setState(() => _mode = _ViewMode.unclaimed);
    }
  }

  void _populateForm(Map<String, dynamic> raw) {
    _nameCtrl.text   = (raw['name']  ?? '').toString();
    _addrCtrl.text   = (raw['addr']  ?? '').toString();
    _ph1Ctrl.text    = (raw['ph']    ?? '').toString();
    _ph2Ctrl.text    = (raw['ph2']   ?? '').toString();
    _notesCtrl.text  = (raw['notes'] ?? '').toString();
    _areaCtrl.text   = (raw['area']  ?? '').toString();
    _profileImageCtrl.text = _readImageUrl(raw);
    final dynamic rawHash = raw['image_blurhash'];
    final String hash = rawHash?.toString().trim() ?? '';
    _profileBlurhash = hash.isEmpty ? null : hash;
    final String gove = (raw['gove'] ?? '').toString();
    _loadedDoctorSpecForMedicalUi = (raw['spec'] ?? '').toString();
    _selectedGove = kGovernorates.contains(gove) ? gove : null;
    _latitude  = _parseDouble(raw['latitude'])  ?? _parseDouble(raw['lat']);
    _longitude = _parseDouble(raw['longitude']) ?? _parseDouble(raw['lng']);
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  String _readImageUrl(Map<String, dynamic> raw) {
    for (final String key in <String>[
      'profile_image_url', 'image_url', 'photo_url', 'avatar_url', 'img',
    ]) {
      final String v = (raw[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) {
      setState(() { _results = <Map<String, dynamic>>[]; _searchError = null; });
      return;
    }
    setState(() { _searching = true; _searchError = null; });
    try {
      final List<dynamic> rows = await _db
          .from(AppEndpoints.doctors)
          .select('id, spec, name, addr, area, ph, gove, owner_user_id')
          .or('name.ilike.%$q%,ph.ilike.%$q%')
          .limit(25);
      if (!mounted) return;
      setState(() { _results = rows.cast<Map<String, dynamic>>(); _searching = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _searching = false; _searchError = 'تعذّر البحث. تحقق من الاتصال بالإنترنت.'; });
    }
  }

  Future<void> _claimClinic(Map<String, dynamic> row) async {
    final String clinicName = (row['name'] ?? '').toString();
    final int doctorId = row['id'] as int;
    final String? uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تأكيد الطلب'),
          content: Text(
            'هل أنت المسؤول عن:\n\n"$clinicName"؟\n\nسيُرسل طلبك إلى الإدارة للمراجعة.',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('نعم، أرسل الطلب')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _db.from(AppEndpoints.clinicClaimRequests).insert(<String, dynamic>{
        'doctor_id': doctorId,
        'user_id':   uid,
        'clinic_name': clinicName,
      });
      if (!mounted) return;
      await _loadMyClinic();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        _showSnack('لديك طلب معلّق بالفعل. انتظر الموافقة أو ألغِه أولاً.');
      } else {
        _showSnack('تعذّر إرسال الطلب: ${e.message}');
      }
    } catch (e) {
      if (mounted) _showSnack('تعذّر إرسال الطلب: ${e.toString()}');
    }
  }

  Future<void> _cancelClaimRequest() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إلغاء الطلب'),
          content: const Text('هل تريد إلغاء طلب الاستحواذ على العيادة؟'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('لا')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم، إلغاء الطلب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _db.from(AppEndpoints.clinicClaimRequests)
          .delete()
          .eq('id', _pendingRequestId!)
          .eq('status', 'pending');
      if (!mounted) return;
      setState(() {
        _pendingRequestId  = null;
        _pendingClinicName = null;
        _pendingCreatedAt  = null;
        _mode    = _ViewMode.unclaimed;
        _results = <Map<String, dynamic>>[];
        _searchCtrl.clear();
      });
    } catch (_) {
      if (mounted) _showSnack('تعذّر إلغاء الطلب.');
    }
  }

  Future<void> _saveClinic() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      _showSnack('يرجى تحديد موقع العيادة على الخريطة.');
      return;
    }
    final MedicalCategorySelectorState? med = _medicalCategoryKey.currentState;
    if (med == null || !med.validateSelection()) {
      _showSnack('يرجى اختيار المجال الطبي والتخصص');
      return;
    }
    final String specOut = med.composeStoredSpec();
    final int? id  = _clinicRaw?['id'] as int?;
    final String? uid = _db.auth.currentUser?.id;
    if (id == null || uid == null) return;

    setState(() { _saving = true; _saveError = null; _saveSuccess = false; });
    try {
      await _db.from(AppEndpoints.doctors).update(<String, dynamic>{
        'name':              _nameCtrl.text.trim(),
        'spec':              specOut,
        'gove':              _selectedGove ?? '',
        'area':              _areaCtrl.text.trim(),
        'addr':              _addrCtrl.text.trim(),
        'ph':                _ph1Ctrl.text.trim(),
        'ph2':               _ph2Ctrl.text.trim(),
        'notes':             _notesCtrl.text.trim(),
        'latitude':          _latitude,
        'longitude':         _longitude,
        'profile_image_url': _profileImageCtrl.text.trim(),
      }).eq('id', id).eq('owner_user_id', uid);

      if (!mounted) return;
      _clinicRaw = <String, dynamic>{
        ..._clinicRaw!,
        'name': _nameCtrl.text.trim(), 'spec': specOut,
        'gove': _selectedGove ?? '',   'area': _areaCtrl.text.trim(),
        'addr': _addrCtrl.text.trim(), 'ph':   _ph1Ctrl.text.trim(),
        'ph2':  _ph2Ctrl.text.trim(),  'notes': _notesCtrl.text.trim(),
        'latitude': _latitude,         'longitude': _longitude,
        'profile_image_url': _profileImageCtrl.text.trim(),
      };
      _loadedDoctorSpecForMedicalUi = specOut;
      setState(() { _saving = false; _saveSuccess = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _saveError = e.toString(); });
    }
  }

  Future<void> _pickAndUploadProfileImage() async {
    final int? doctorId = _clinicRaw?['id'] as int?;
    final String? uid = _db.auth.currentUser?.id;
    if (doctorId == null || uid == null) {
      _showSnack('تعذّر تحديد بيانات الحساب لرفع الصورة.');
      return;
    }
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 95, maxWidth: 2000,
      );
      if (picked == null || !mounted) return;

      setState(() => _uploadingProfileImage = true);
      final Uint8List bytes = await picked.readAsBytes();
      if (!mounted) return;

      // Compress to WebP + generate BlurHash for placeholder.
      final ProcessedImageResult processed =
          await ImageProcessingService.compressAndHash(
        original: bytes,
        quality: 75,
      );
      if (!mounted) return;

      final String path =
          '$uid/$doctorId/profile_${DateTime.now().millisecondsSinceEpoch}.${processed.fileExtension}';
      final String oldImageUrl = _profileImageCtrl.text.trim();

      await _db.storage.from(AppEndpoints.clinicProfileImages).uploadBinary(
            path,
            processed.bytes,
            fileOptions:
                FileOptions(upsert: true, contentType: processed.contentType),
          );
      final String imageUrl =
          _db.storage.from(AppEndpoints.clinicProfileImages).getPublicUrl(path);

      // Persist BlurHash next to the new URL so cards can render an instant
      // placeholder (instead of leaving the column stale from the previous image).
      try {
        await _db
            .from(AppEndpoints.doctors)
            .update(<String, dynamic>{
              'profile_image_url': imageUrl,
              'image_blurhash': processed.blurhash.isEmpty
                  ? null
                  : processed.blurhash,
            })
            .eq('id', doctorId);
      } catch (_) {
        // Falls through to old behaviour: card without blurhash.
      }

      await _tryDeleteProfileImageByUrl(oldImageUrl);

      if (!mounted) return;
      setState(() {
        _profileImageCtrl.text = imageUrl;
        _profileBlurhash =
            processed.blurhash.isEmpty ? null : processed.blurhash;
        if (_saveSuccess) _saveSuccess = false;
        if (_saveError != null) _saveError = null;
      });
      _showSnack('تم رفع الصورة. اضغط "حفظ التغييرات" لتثبيتها.');
    } catch (e) {
      if (mounted) _showSnack('تعذّر رفع الصورة: $e');
    } finally {
      if (mounted) setState(() => _uploadingProfileImage = false);
    }
  }

  String? _storagePathFromPublicUrl(String imageUrl) {
    final Uri? uri = Uri.tryParse(imageUrl.trim());
    if (uri == null) return null;
    const String prefix = '/storage/v1/object/public/clinic-profile-images/';
    if (!uri.path.contains(prefix)) return null;
    final String encoded = uri.path.split(prefix).last;
    return encoded.isEmpty ? null : Uri.decodeComponent(encoded);
  }

  Future<void> _tryDeleteProfileImageByUrl(String imageUrl) async {
    final String? path = _storagePathFromPublicUrl(imageUrl);
    if (path == null) return;
    try {
      await _db.storage
          .from(AppEndpoints.clinicProfileImages)
          .remove(<String>[path]);
    } catch (_) {}
  }

  Future<void> _unlinkClinic() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إلغاء الارتباط'),
          content: const Text(
            'هل تريد إلغاء ارتباط حسابك بهذه العيادة؟\nلن يتأثر سجل العيادة.',
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم، إلغاء الارتباط'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final int? id = _clinicRaw?['id'] as int?;
    if (id == null) return;
    try {
      await _db.from(AppEndpoints.doctors)
          .update(<String, dynamic>{'owner_user_id': null})
          .eq('id', id)
          .eq('owner_user_id', _db.auth.currentUser!.id);
      if (!mounted) return;
      setState(() {
        _clinicRaw = null;
        _mode      = _ViewMode.unclaimed;
        _results   = <Map<String, dynamic>>[];
        _searchCtrl.clear();
      });
    } catch (_) {
      if (mounted) _showSnack('تعذّر إلغاء الارتباط.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  AppBar _buildAppBar({List<Widget>? extraActions}) {
    return AppBar(
      backgroundColor: const Color(0xFF42A5F5),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      title: Text('عيادتي', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
      actions: <Widget>[
        if (extraActions != null) ...extraActions,
        IconButton(
          icon: const Icon(Icons.logout_outlined),
          tooltip: 'تسجيل الخروج',
          onPressed: _signOut,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _ViewMode.checking             => _buildChecking(),
      _ViewMode.unclaimed            => _buildUnclaimed(),
      _ViewMode.claimPending         => _buildClaimPending(),
      _ViewMode.verificationNotStarted => _buildVerificationNotStarted(),
      _ViewMode.verificationPending  => _buildVerificationPending(),
      _ViewMode.verificationRejected => _buildVerificationRejected(),
      _ViewMode.editing              => _buildEditing(),
    };
  }

  // ─── Checking ───────────────────────────────────────────────────────────────

  Widget _buildChecking() {
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
      ),
    );
  }

  // ─── Unclaimed ──────────────────────────────────────────────────────────────

  Widget _buildUnclaimed() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(),
        body: Column(
          children: <Widget>[
            _buildUnclaimedHeader(),
            Expanded(child: _buildSearchSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildUnclaimedHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(bottom: BorderSide(color: Color(0xFFE3E8F0))),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle),
            child: const Icon(Icons.store_outlined, size: 40, color: Color(0xFF42A5F5)),
          ),
          const SizedBox(height: 12),
          Text('اربط عيادتك',
              style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
          const SizedBox(height: 4),
          Text(
            'ابحث عن عيادتك باسمها أو رقم هاتفها لتتمكن من إدارة بياناتها.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B), height: 1.5),
          ),
          const SizedBox(height: 16),
          _buildSearchField(),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        hintText: 'اسم الطبيب أو رقم الهاتف...',
        hintStyle: GoogleFonts.cairo(color: const Color(0xFF90A4AE)),
        filled: true,
        fillColor: const Color(0xFFF7FBFF),
        prefixIcon: const Icon(Icons.search, color: Color(0xFF42A5F5)),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      onChanged: _onSearchChanged,
      onSubmitted: _runSearch,
    );
  }

  Widget _buildSearchSection() {
    if (_searchError != null) {
      return Center(child: Text(_searchError!, style: GoogleFonts.cairo(color: Colors.red.shade700)));
    }
    if (_results.isEmpty && _searchCtrl.text.trim().isNotEmpty && !_searching) {
      return Center(child: Text('لا توجد نتائج. جرّب اسماً آخر.', style: GoogleFonts.cairo(color: const Color(0xFF90A4AE))));
    }
    if (_results.isEmpty) {
      return Center(child: Text('ابدأ بكتابة اسمك أو رقم هاتفك.', style: GoogleFonts.cairo(color: const Color(0xFFB0BEC5))));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (_, int i) => _buildSearchResultCard(_results[i]),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> row) {
    final String name    = (row['name']  ?? '').toString();
    final String spec    = (row['spec']  ?? '').toString();
    final String area    = (row['area']  ?? '').toString();
    final String gove    = (row['gove']  ?? '').toString();
    final String ph      = (row['ph']    ?? '').toString();
    final bool isClaimed = row['owner_user_id'] != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF1D3557))),
                  const SizedBox(height: 2),
                  Text('$spec • $area - $gove', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF607D8B))),
                  if (ph.isNotEmpty)
                    Text(ph, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF90A4AE))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isClaimed
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF1F3F5), borderRadius: BorderRadius.circular(8)),
                    child: Text('مُرتبط', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF90A4AE))),
                  )
                : FilledButton(
                    onPressed: () => _claimClinic(row),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF42A5F5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('هذه عيادتي'),
                  ),
          ],
        ),
      ),
    );
  }

  // ─── Claim Pending ──────────────────────────────────────────────────────────

  Widget _buildClaimPending() {
    final String clinicName = _pendingClinicName ?? '';
    final String dateStr = _pendingCreatedAt != null
        ? '${_pendingCreatedAt!.day}/${_pendingCreatedAt!.month}/${_pendingCreatedAt!.year}'
        : '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFFFFF8E1), shape: BoxShape.circle),
                  child: const Icon(Icons.hourglass_top_rounded, size: 48, color: Color(0xFFF9A825)),
                ),
                const SizedBox(height: 24),
                Text('طلب الارتباط قيد المراجعة',
                    style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
                const SizedBox(height: 8),
                Text(
                  'سيتم مراجعة طلبك والموافقة عليه من قِبَل الإدارة قريباً.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF607D8B), height: 1.6),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildInfoRow(icon: Icons.store_outlined, label: 'العيادة المطلوبة',
                          value: clinicName.isNotEmpty ? clinicName : '—'),
                      if (dateStr.isNotEmpty) ...<Widget>[
                        const Divider(height: 20),
                        _buildInfoRow(icon: Icons.calendar_today_outlined, label: 'تاريخ الطلب', value: dateStr),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _cancelClaimRequest,
                    icon: const Icon(Icons.cancel_outlined, color: Color(0xFFB71C1C)),
                    label: Text('إلغاء الطلب',
                        style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFFB71C1C))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF9A9A)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Verification — Not Started ─────────────────────────────────────────────

  Widget _buildVerificationNotStarted() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(extraActions: <Widget>[_unlinkMenu()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFFE3F2FD), shape: BoxShape.circle),
                  child: const Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFF1565C0)),
                ),
                const SizedBox(height: 24),
                Text('قم بتوثيق حسابك لإدارة عيادتك',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
                const SizedBox(height: 10),
                Text(
                  'لفتح ميزات إدارة العيادة الكاملة، يجب توثيق هويتك وإجازتك المهنية.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF607D8B), height: 1.6),
                ),
                const SizedBox(height: 32),
                LoadingButton(
                  label: 'ابدأ التوثيق الآن',
                  icon: Icons.verified_outlined,
                  onPressed: () async {
                    final bool? result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => const SubmitVerificationScreen(),
                      ),
                    );
                    if (result == true && mounted) _loadMyClinic();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Verification — Pending ─────────────────────────────────────────────────

  Widget _buildVerificationPending() {
    final VerificationRequestModel? req = _verificationRequest;
    final String dateStr = req != null
        ? '${req.createdAt.day}/${req.createdAt.month}/${req.createdAt.year}'
        : '';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(extraActions: <Widget>[_unlinkMenu()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFFFFF8E1), shape: BoxShape.circle),
                  child: const Icon(Icons.hourglass_top_rounded, size: 48, color: Color(0xFFF9A825)),
                ),
                const SizedBox(height: 24),
                Text('طلبك قيد المراجعة',
                    style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
                const SizedBox(height: 8),
                Text(
                  'سنعلمك بالنتيجة قريباً. شكراً لصبرك.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF607D8B), height: 1.6),
                ),
                if (dateStr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildInfoRow(icon: Icons.calendar_today_outlined, label: 'تاريخ الإرسال', value: dateStr),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Verification — Rejected ─────────────────────────────────────────────────

  Widget _buildVerificationRejected() {
    final String notes = _verificationRequest?.adminNotes?.isNotEmpty == true
        ? _verificationRequest!.adminNotes!
        : 'لم يُحدَّد سبب. يرجى إعادة الإرسال مع مستندات صحيحة.';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(extraActions: <Widget>[_unlinkMenu()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFFFFEBEE), shape: BoxShape.circle),
                  child: const Icon(Icons.cancel_outlined, size: 48, color: Color(0xFFC62828)),
                ),
                const SizedBox(height: 24),
                Text('تم رفض طلب التوثيق',
                    style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Text(
                    'سبب الرفض:\n$notes',
                    style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFFC62828), height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                LoadingButton(
                  label: 'إعادة إرسال الطلب',
                  icon: Icons.refresh,
                  onPressed: () async {
                    final bool? result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => const SubmitVerificationScreen(),
                      ),
                    );
                    if (result == true && mounted) _loadMyClinic();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Editing (Verified Hub) ──────────────────────────────────────────────────

  Widget _buildEditing() {
    final DoctorStatus currentStatus = DoctorStatusX.fromString(
        (_clinicRaw?['current_status'] as String?));
    final String? statusMessage = _clinicRaw?['status_message'] as String?;
    final String? expiresAtRaw  = _clinicRaw?['status_expires_at'] as String?;
    final DateTime? expiresAt   = expiresAtRaw != null
        ? DateTime.tryParse(expiresAtRaw)
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        appBar: _buildAppBar(extraActions: <Widget>[_unlinkMenu()]),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildEditHeader(),
              const SizedBox(height: 16),
              // Quick Status Widget
              QuickStatusWidget(
                doctorId:       (_clinicRaw?['id'] as int?) ?? 0,
                initialStatus:  currentStatus,
                initialMessage: statusMessage,
                initialExpiresAt: expiresAt,
              ),
              const SizedBox(height: 16),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(controller: _nameCtrl, label: 'اسم العيادة / الطبيب', icon: Icons.person_outline,
                    validator: (String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: MedicalCategorySelector(
                    key: _medicalCategoryKey,
                    initialStoredSpec: _loadedDoctorSpecForMedicalUi,
                    decorateDropdownField: (String labelText) => InputDecoration(
                      labelText: labelText,
                      labelStyle: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B)),
                      filled: true,
                      fillColor: const Color(0xFFF2F7FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    introHeadingStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _buildDropdown(label: 'المحافظة', icon: Icons.location_city_outlined,
                    value: _selectedGove, items: kGovernorates,
                    onChanged: (String? v) => setState(() => _selectedGove = v)),
                const Divider(height: 1),
                _buildTextInput(controller: _areaCtrl, label: 'المنطقة / الحي', icon: Icons.place_outlined),
                const Divider(height: 1),
                _buildTextInput(controller: _addrCtrl, label: 'العنوان التفصيلي', icon: Icons.home_outlined),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: addClinicStyleMapLocationBlock(
                    latitude:  _latitude,
                    longitude: _longitude,
                    onChanged: (double? lat, double? lng) {
                      setState(() {
                        _latitude  = lat;
                        _longitude = lng;
                        if (_saveSuccess) _saveSuccess = false;
                        if (_saveError != null) _saveError = null;
                      });
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(controller: _ph1Ctrl, label: 'رقم الهاتف الأول', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                const Divider(height: 1),
                _buildTextInput(controller: _ph2Ctrl, label: 'رقم الهاتف الثاني (اختياري)', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _buildBlurhashAvatar(
                            radius: 26,
                            url: _profileImageCtrl.text.trim(),
                            blurhash: _profileBlurhash,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('صورة البروفايل',
                                textDirection: TextDirection.rtl,
                                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1D3557))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _uploadingProfileImage ? null : _pickAndUploadProfileImage,
                              icon: _uploadingProfileImage
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.photo_library_outlined),
                              label: Text(_uploadingProfileImage ? 'جارٍ الرفع...' : 'اختيار من المعرض',
                                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          if (_profileImageCtrl.text.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'حذف الصورة',
                              onPressed: () async {
                                final String old = _profileImageCtrl.text.trim();
                                await _tryDeleteProfileImageByUrl(old);
                                if (!mounted) return;
                                setState(() {
                                  _profileImageCtrl.clear();
                                  if (_saveSuccess) _saveSuccess = false;
                                  if (_saveError != null) _saveError = null;
                                });
                              },
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFB71C1C)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(controller: _notesCtrl, label: 'ملاحظات (مواعيد العمل، خدمات...)',
                    icon: Icons.notes_outlined, maxLines: 3),
              ]),
              const SizedBox(height: 20),
              if (_saveSuccess)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle_outline, color: Color(0xFF388E3C)),
                      const SizedBox(width: 8),
                      Text('تم حفظ التغييرات بنجاح.',
                          style: GoogleFonts.cairo(color: const Color(0xFF388E3C), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              if (_saveError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Text('حدث خطأ: $_saveError',
                      style: GoogleFonts.cairo(color: Colors.red.shade700)),
                ),
              LoadingButton(
                label: _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _saveClinic,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unlinkMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (String v) { if (v == 'unlink') _unlinkClinic(); },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'unlink', child: Text('إلغاء الارتباط')),
      ],
    );
  }

  Widget _buildEditHeader() {
    final String name     = (_clinicRaw?['name'] ?? '').toString();
    final String spec     = (_clinicRaw?['spec']  ?? '').toString();
    final String imageUrl = _profileImageCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFE3F2FD), shape: BoxShape.circle),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE3F2FD),
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? const Icon(Icons.store_rounded, color: Color(0xFF42A5F5), size: 28)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name.isNotEmpty ? name : 'عيادتك',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1D3557))),
                if (spec.isNotEmpty)
                  Text(spec, style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.verified, size: 14, color: Color(0xFF388E3C)),
                const SizedBox(width: 4),
                Text('موثّق', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF388E3C), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: const Color(0xFF90A4AE)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF90A4AE))),
            Text(value, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1D3557))),
          ],
        ),
      ],
    );
  }

  Widget _buildFieldCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textDirection: TextDirection.rtl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: (_) {
        if (_saveSuccess) setState(() => _saveSuccess = false);
        if (_saveError != null) setState(() => _saveError = null);
        if (controller == _profileImageCtrl) setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B)),
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF1D3557)),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B)),
          prefixIcon: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        ),
        style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF1D3557)),
        items: items.map((String s) => DropdownMenuItem<String>(
          value: s, child: Text(s, style: GoogleFonts.cairo(fontSize: 14)),
        )).toList(),
        onChanged: (String? v) {
          onChanged(v);
          if (_saveSuccess) setState(() => _saveSuccess = false);
          if (_saveError != null) setState(() => _saveError = null);
        },
      ),
    );
  }

  /// Avatar that fades-in over a BlurHash placeholder (or a tinted icon when
  /// neither is available). Falls back gracefully on bad blurhashes.
  Widget _buildBlurhashAvatar({
    required double radius,
    required String url,
    required String? blurhash,
  }) {
    final double size = radius * 2;
    Widget placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFFE3F2FD),
      alignment: Alignment.center,
      child: const Icon(Icons.person_outline, color: Color(0xFF42A5F5)),
    );
    if (blurhash != null && blurhash.isNotEmpty) {
      try {
        placeholder = SizedBox(
          width: size,
          height: size,
          child: BlurHash(hash: blurhash),
        );
      } catch (_) {
        // keep default placeholder on bad hash
      }
    }

    final Widget child = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? p) {
                  if (p == null) return child;
                  return placeholder;
                },
                errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                    placeholder,
              ),
      ),
    );
    return child;
  }
}
