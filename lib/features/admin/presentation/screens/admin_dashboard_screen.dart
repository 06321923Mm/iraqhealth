import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../features/verification/data/models/verification_request_model.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SupabaseClient _db = Supabase.instance.client;

  int _totalDoctors   = 0;
  int _pendingVerif   = 0;
  int _onlineNow      = 0;
  bool _loading       = true;

  List<Map<String, dynamic>> _recentVerifRequests = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      // Total doctors
      final List<dynamic> totalRes = await _db
          .from(AppEndpoints.doctors)
          .select('id');
      // Pending verification
      final List<dynamic> pendingRes = await _db
          .from(AppEndpoints.verificationRequests)
          .select('id')
          .eq('status', 'pending');
      // Online now
      final List<dynamic> onlineRes = await _db
          .from(AppEndpoints.doctors)
          .select('id')
          .eq('current_status', 'online');
      // Recent verification requests (last 5)
      final List<dynamic> recentRes = await _db
          .from(AppEndpoints.verificationRequests)
          .select('id, doctor_id, status, created_at, admin_notes')
          .order('created_at', ascending: false)
          .limit(5);

      if (!mounted) return;
      setState(() {
        _totalDoctors          = totalRes.length;
        _pendingVerif          = pendingRes.length;
        _onlineNow             = onlineRes.length;
        _recentVerifRequests   = recentRes.cast<Map<String, dynamic>>();
        _loading               = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  _buildRecentSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('الرئيسية',
                  style: GoogleFonts.cairo(
                      fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
              Text('نظرة عامة على حالة التطبيق',
                  style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B))),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadStats,
          icon: const Icon(Icons.refresh, color: Color(0xFF42A5F5)),
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _StatCard(
          label:  'إجمالي الأطباء المسجلين',
          value:  _totalDoctors.toString(),
          icon:   Icons.people_outline,
          color:  const Color(0xFF42A5F5),
        ),
        _StatCard(
          label:  'طلبات التوثيق المعلقة',
          value:  _pendingVerif.toString(),
          icon:   Icons.pending_actions_outlined,
          color:  const Color(0xFFF9A825),
        ),
        _StatCard(
          label:  'العيادات المتاحة الآن',
          value:  _onlineNow.toString(),
          icon:   Icons.circle,
          color:  const Color(0xFF388E3C),
        ),
      ],
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('آخر طلبات التوثيق',
            style: GoogleFonts.cairo(
                fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
        const SizedBox(height: 12),
        if (_recentVerifRequests.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('لا توجد طلبات حتى الآن.',
                  style: GoogleFonts.cairo(color: const Color(0xFF90A4AE))),
            ),
          )
        else
          ...(_recentVerifRequests.map((Map<String, dynamic> req) {
            final VerificationStatus status =
                VerificationStatusX.fromString(req['status'] as String?);
            final String date = _formatDate(req['created_at'] as String?);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    _StatusDot(status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'طلب توثيق',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFF1D3557)),
                          ),
                          Text(date, style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF90A4AE))),
                        ],
                      ),
                    ),
                    _statusChip(status),
                  ],
                ),
              ),
            );
          })),
      ],
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final DateTime dt = DateTime.tryParse(iso) ?? DateTime.now();
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _statusChip(VerificationStatus status) {
    final (String label, Color color, Color bg) = switch (status) {
      VerificationStatus.pending  => ('معلّق',   const Color(0xFFF9A825), const Color(0xFFFFF8E1)),
      VerificationStatus.approved => ('مقبول',   const Color(0xFF388E3C), const Color(0xFFE8F5E9)),
      VerificationStatus.rejected => ('مرفوض',   const Color(0xFFC62828), const Color(0xFFFFEBEE)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.status);
  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      VerificationStatus.pending  => const Color(0xFFF9A825),
      VerificationStatus.approved => const Color(0xFF388E3C),
      VerificationStatus.rejected => const Color(0xFFC62828),
    };
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: GoogleFonts.cairo(
                  fontSize: 26, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557))),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF607D8B), height: 1.4)),
        ],
      ),
    );
  }
}
