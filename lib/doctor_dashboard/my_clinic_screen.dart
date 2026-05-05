import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../doctor_constants.dart';

const String _kTable = 'doctors';
const String _kClaimsTable = 'clinic_claim_requests';

enum _ViewMode { checking, unclaimed, pending, editing }

class MyClinicScreen extends StatefulWidget {
  const MyClinicScreen({super.key});

  @override
  State<MyClinicScreen> createState() => _MyClinicScreenState();
}

class _MyClinicScreenState extends State<MyClinicScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  _ViewMode _mode = _ViewMode.checking;

  // بيانات العيادة المرتبطة (خام من Supabase)
  Map<String, dynamic>? _clinicRaw;

  // بيانات الطلب المعلّق
  String? _pendingRequestId;
  String? _pendingClinicName;
  DateTime? _pendingCreatedAt;

  // حالة البحث
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;

  // حالة نموذج التعديل
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addrCtrl = TextEditingController();
  final TextEditingController _ph1Ctrl = TextEditingController();
  final TextEditingController _ph2Ctrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _areaCtrl = TextEditingController();
  String? _selectedSpec;
  String? _selectedGove;
  bool _saving = false;
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
      // 1. هل العيادة مرتبطة بالفعل؟
      final List<dynamic> owned = await _db
          .from(_kTable)
          .select('id, spec, name, addr, area, ph, ph2, notes, gove, owner_user_id')
          .eq('owner_user_id', uid)
          .limit(1);
      if (!mounted) return;

      if (owned.isNotEmpty) {
        final Map<String, dynamic> raw = owned.first as Map<String, dynamic>;
        _populateForm(raw);
        setState(() {
          _clinicRaw = raw;
          _mode = _ViewMode.editing;
        });
        return;
      }

      // 2. هل يوجد طلب معلّق؟
      final List<dynamic> pending = await _db
          .from(_kClaimsTable)
          .select('id, clinic_name, created_at')
          .eq('user_id', uid)
          .eq('status', 'pending')
          .limit(1);
      if (!mounted) return;

      if (pending.isNotEmpty) {
        final Map<String, dynamic> req = pending.first as Map<String, dynamic>;
        setState(() {
          _pendingRequestId = req['id'] as String?;
          _pendingClinicName = (req['clinic_name'] ?? '').toString();
          _pendingCreatedAt = req['created_at'] != null
              ? DateTime.tryParse(req['created_at'].toString())
              : null;
          _mode = _ViewMode.pending;
        });
        return;
      }

      setState(() => _mode = _ViewMode.unclaimed);
    } catch (_) {
      if (mounted) setState(() => _mode = _ViewMode.unclaimed);
    }
  }

  void _populateForm(Map<String, dynamic> raw) {
    _nameCtrl.text = (raw['name'] ?? '').toString();
    _addrCtrl.text = (raw['addr'] ?? '').toString();
    _ph1Ctrl.text = (raw['ph'] ?? '').toString();
    _ph2Ctrl.text = (raw['ph2'] ?? '').toString();
    _notesCtrl.text = (raw['notes'] ?? '').toString();
    _areaCtrl.text = (raw['area'] ?? '').toString();
    final String spec = (raw['spec'] ?? '').toString();
    final String gove = (raw['gove'] ?? '').toString();
    _selectedSpec = kPhysicianSpecializations.contains(spec) ? spec : null;
    _selectedGove = kGovernorates.contains(gove) ? gove : null;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) {
      setState(() {
        _results = <Map<String, dynamic>>[];
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final List<dynamic> rows = await _db
          .from(_kTable)
          .select('id, spec, name, addr, area, ph, gove, owner_user_id')
          .or('name.ilike.%$q%,ph.ilike.%$q%')
          .limit(25);
      if (!mounted) return;
      setState(() {
        _results = rows.cast<Map<String, dynamic>>();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'تعذّر البحث. تحقق من الاتصال بالإنترنت.';
      });
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تأكيد الطلب'),
          content: Text(
            'هل أنت المسؤول عن:\n\n"$clinicName"؟\n\nسيُرسل طلبك إلى الإدارة للمراجعة والموافقة قبل ربط حسابك بالعيادة.',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم، أرسل الطلب'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _db.from(_kClaimsTable).insert(<String, dynamic>{
        'doctor_id': doctorId,
        'user_id': uid,
        'clinic_name': clinicName,
      });
      if (!mounted) return;
      await _loadMyClinic();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // unique constraint: طلب معلّق موجود مسبقاً
      if (e.code == '23505') {
        _showSnack('لديك طلب معلّق بالفعل. انتظر الموافقة أو ألغِه أولاً.');
      } else {
        _showSnack('تعذّر إرسال الطلب: ${e.message}');
      }
    } catch (e) {
      if (mounted) _showSnack('تعذّر إرسال الطلب: ${e.toString()}');
    }
  }

  Future<void> _cancelRequest() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إلغاء الطلب'),
          content: const Text('هل تريد إلغاء طلب الاستحواذ على العيادة؟'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('لا'),
            ),
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
      await _db
          .from(_kClaimsTable)
          .delete()
          .eq('id', _pendingRequestId!)
          .eq('status', 'pending');
      if (!mounted) return;
      setState(() {
        _pendingRequestId = null;
        _pendingClinicName = null;
        _pendingCreatedAt = null;
        _mode = _ViewMode.unclaimed;
        _results = <Map<String, dynamic>>[];
        _searchCtrl.clear();
      });
    } catch (e) {
      if (mounted) _showSnack('تعذّر إلغاء الطلب.');
    }
  }

  Future<void> _saveClinic() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final int? id = _clinicRaw?['id'] as int?;
    if (id == null) return;
    final String? uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
      _saveSuccess = false;
    });
    try {
      await _db.from(_kTable).update(<String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'spec': _selectedSpec ?? '',
        'gove': _selectedGove ?? '',
        'area': _areaCtrl.text.trim(),
        'addr': _addrCtrl.text.trim(),
        'ph': _ph1Ctrl.text.trim(),
        'ph2': _ph2Ctrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      }).eq('id', id).eq('owner_user_id', uid);

      if (!mounted) return;
      _clinicRaw = <String, dynamic>{
        ..._clinicRaw!,
        'name': _nameCtrl.text.trim(),
        'spec': _selectedSpec ?? '',
        'gove': _selectedGove ?? '',
        'area': _areaCtrl.text.trim(),
        'addr': _addrCtrl.text.trim(),
        'ph': _ph1Ctrl.text.trim(),
        'ph2': _ph2Ctrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };
      setState(() {
        _saving = false;
        _saveSuccess = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.toString();
      });
    }
  }

  Future<void> _unlinkClinic() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إلغاء الارتباط'),
          content: const Text(
            'هل تريد إلغاء ارتباط حسابك بهذه العيادة؟\nلن يتأثر سجل العيادة، لكنك لن تتمكن من تعديله.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
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
      await _db
          .from(_kTable)
          .update(<String, dynamic>{'owner_user_id': null})
          .eq('id', id)
          .eq('owner_user_id', _db.auth.currentUser!.id);
      if (!mounted) return;
      setState(() {
        _clinicRaw = null;
        _mode = _ViewMode.unclaimed;
        _results = <Map<String, dynamic>>[];
        _searchCtrl.clear();
      });
    } catch (e) {
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

  // ─── البناء الرئيسي ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _ViewMode.checking => _buildChecking(),
      _ViewMode.unclaimed => _buildUnclaimed(),
      _ViewMode.pending => _buildPending(),
      _ViewMode.editing => _buildEditing(),
    };
  }

  Widget _buildChecking() {
    return const Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }

  // ─── حالة: لم يُربط حساب بعد ─────────────────────────────────────────────

  Widget _buildUnclaimed() {
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
            'عيادتي',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
        ),
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE3E8F0)),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFE3F2FD),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.store_outlined,
              size: 40,
              color: Color(0xFF42A5F5),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'اربط عيادتك',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1D3557),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ابحث عن عيادتك باسمها أو رقم هاتفها لتتمكن من إدارة بياناتها.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: const Color(0xFF607D8B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
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
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCFD8DC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCFD8DC)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF42A5F5), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: _runSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    if (_searchError != null) {
      return Center(
        child: Text(
          _searchError!,
          style: GoogleFonts.cairo(color: Colors.red.shade700),
        ),
      );
    }
    if (_results.isEmpty && _searchCtrl.text.trim().isNotEmpty && !_searching) {
      return Center(
        child: Text(
          'لا توجد نتائج. جرّب اسماً آخر أو رقم هاتف.',
          style: GoogleFonts.cairo(color: const Color(0xFF90A4AE)),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'ابدأ بكتابة اسمك أو رقم هاتفك.',
          style: GoogleFonts.cairo(color: const Color(0xFFB0BEC5)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int i) =>
          _buildSearchResultCard(_results[i]),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> row) {
    final String name = (row['name'] ?? '').toString();
    final String spec = (row['spec'] ?? '').toString();
    final String area = (row['area'] ?? '').toString();
    final String gove = (row['gove'] ?? '').toString();
    final String ph = (row['ph'] ?? '').toString();
    final bool isClaimed = row['owner_user_id'] != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: const Color(0xFF1D3557),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$spec • $area - $gove',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: const Color(0xFF607D8B),
                    ),
                  ),
                  if (ph.isNotEmpty)
                    Text(
                      ph,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: const Color(0xFF90A4AE),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isClaimed
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'مُرتبط',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: const Color(0xFF90A4AE),
                      ),
                    ),
                  )
                : FilledButton(
                    onPressed: () => _claimClinic(row),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF42A5F5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('هذه عيادتي'),
                  ),
          ],
        ),
      ),
    );
  }

  // ─── حالة: طلب قيد المراجعة ──────────────────────────────────────────────

  Widget _buildPending() {
    final String clinicName = _pendingClinicName ?? '';
    final String dateStr = _pendingCreatedAt != null
        ? '${_pendingCreatedAt!.day}/${_pendingCreatedAt!.month}/${_pendingCreatedAt!.year}'
        : '';

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
            'عيادتي',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF8E1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    size: 48,
                    color: Color(0xFFF9A825),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'طلبك قيد المراجعة',
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1D3557),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'سيتم مراجعة طلبك من قِبَل الإدارة والموافقة عليه قريباً.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: const Color(0xFF607D8B),
                    height: 1.6,
                  ),
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
                      _buildInfoRow(
                        icon: Icons.store_outlined,
                        label: 'العيادة المطلوبة',
                        value: clinicName.isNotEmpty ? clinicName : '—',
                      ),
                      if (dateStr.isNotEmpty) ...<Widget>[
                        const Divider(height: 20),
                        _buildInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'تاريخ الطلب',
                          value: dateStr,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _cancelRequest,
                    icon: const Icon(Icons.cancel_outlined,
                        color: Color(0xFFB71C1C)),
                    label: Text(
                      'إلغاء الطلب',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFB71C1C),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF9A9A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: const Color(0xFF90A4AE)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: const Color(0xFF90A4AE),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D3557),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── حالة: العيادة مرتبطة — نموذج التعديل ───────────────────────────────

  Widget _buildEditing() {
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
            'عيادتي',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
          ),
          actions: <Widget>[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String v) {
                if (v == 'unlink') _unlinkClinic();
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'unlink',
                  child: Text('إلغاء الارتباط'),
                ),
              ],
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildEditHeader(),
              const SizedBox(height: 16),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(
                  controller: _nameCtrl,
                  label: 'اسم العيادة / الطبيب',
                  icon: Icons.person_outline,
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                ),
                const Divider(height: 1),
                _buildDropdown(
                  label: 'التخصص',
                  icon: Icons.medical_services_outlined,
                  value: _selectedSpec,
                  items: kPhysicianSpecializations,
                  onChanged: (String? v) =>
                      setState(() => _selectedSpec = v),
                ),
                const Divider(height: 1),
                _buildDropdown(
                  label: 'المحافظة',
                  icon: Icons.location_city_outlined,
                  value: _selectedGove,
                  items: kGovernorates,
                  onChanged: (String? v) =>
                      setState(() => _selectedGove = v),
                ),
                const Divider(height: 1),
                _buildTextInput(
                  controller: _areaCtrl,
                  label: 'المنطقة / الحي',
                  icon: Icons.place_outlined,
                ),
                const Divider(height: 1),
                _buildTextInput(
                  controller: _addrCtrl,
                  label: 'العنوان التفصيلي',
                  icon: Icons.home_outlined,
                ),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(
                  controller: _ph1Ctrl,
                  label: 'رقم الهاتف الأول',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const Divider(height: 1),
                _buildTextInput(
                  controller: _ph2Ctrl,
                  label: 'رقم الهاتف الثاني (اختياري)',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
              ]),
              const SizedBox(height: 12),
              _buildFieldCard(children: <Widget>[
                _buildTextInput(
                  controller: _notesCtrl,
                  label: 'ملاحظات (مواعيد العمل، خدمات...)',
                  icon: Icons.notes_outlined,
                  maxLines: 3,
                ),
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
                      const Icon(Icons.check_circle_outline,
                          color: Color(0xFF388E3C)),
                      const SizedBox(width: 8),
                      Text(
                        'تم حفظ التغييرات بنجاح.',
                        style: GoogleFonts.cairo(
                            color: const Color(0xFF388E3C),
                            fontWeight: FontWeight.w600),
                      ),
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
                  child: Text(
                    'حدث خطأ: $_saveError',
                    style: GoogleFonts.cairo(color: Colors.red.shade700),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveClinic,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF42A5F5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditHeader() {
    final String name = (_clinicRaw?['name'] ?? '').toString();
    final String spec = (_clinicRaw?['spec'] ?? '').toString();
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
            decoration: const BoxDecoration(
              color: Color(0xFFE3F2FD),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.store_rounded,
              color: Color(0xFF42A5F5),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isNotEmpty ? name : 'عيادتك',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: const Color(0xFF1D3557),
                  ),
                ),
                if (spec.isNotEmpty)
                  Text(
                    spec,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: const Color(0xFF607D8B),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'مرتبطة',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: const Color(0xFF388E3C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(
          fontSize: 13,
          color: const Color(0xFF607D8B),
        ),
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
          labelStyle: GoogleFonts.cairo(
            fontSize: 13,
            color: const Color(0xFF607D8B),
          ),
          prefixIcon: Icon(icon, size: 20, color: const Color(0xFF90A4AE)),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        ),
        style: GoogleFonts.cairo(
          fontSize: 14,
          color: const Color(0xFF1D3557),
        ),
        items: items
            .map(
              (String s) => DropdownMenuItem<String>(
                value: s,
                child: Text(s, style: GoogleFonts.cairo(fontSize: 14)),
              ),
            )
            .toList(),
        onChanged: (String? v) {
          onChanged(v);
          if (_saveSuccess) setState(() => _saveSuccess = false);
          if (_saveError != null) setState(() => _saveError = null);
        },
      ),
    );
  }
}
