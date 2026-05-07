import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_endpoints.dart';
import '../../../../features/verification/data/models/verification_request_model.dart';
import '../screens/clinics_management_screen.dart';
import '../screens/verification_review_screen.dart';

enum _AdminSection { dashboard, verification, clinics }

/// Entry point for the admin hub.
/// Double-guards access: the route handler in main.dart is the primary gate;
/// initState provides defense-in-depth by redirecting if the role check fails.
class AdminHubPage extends StatefulWidget {
  const AdminHubPage({super.key});

  @override
  State<AdminHubPage> createState() => _AdminHubPageState();
}

class _AdminHubPageState extends State<AdminHubPage> {
  _AdminSection _section = _AdminSection.dashboard;
  bool _isChecking = true;

  // Dashboard stats
  final SupabaseClient _db = Supabase.instance.client;
  int _totalDoctors        = 0;
  int _pendingVerif        = 0;
  int _onlineNow           = 0;
  bool _statsLoading       = true;
  List<Map<String, dynamic>> _recentVerifRequests = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final User? user = Supabase.instance.client.auth.currentUser;
      if (user == null || user.userMetadata?['role'] != 'admin') {
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }
      setState(() => _isChecking = false);
      _loadStats();
    });
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final int totalDoctors = await _db
          .from(AppEndpoints.doctors)
          .count(CountOption.exact);
      final int pendingVerif = await _db
          .from(AppEndpoints.verificationRequests)
          .count(CountOption.exact)
          .eq('status', 'pending');
      final int onlineNow = await _db
          .from(AppEndpoints.doctors)
          .count(CountOption.exact)
          .eq('current_status', 'online');
      final List<dynamic> recentRes = await _db
          .from(AppEndpoints.verificationRequests)
          .select('id, doctor_id, status, created_at, admin_notes')
          .order('created_at', ascending: false)
          .limit(5);

      if (!mounted) return;
      setState(() {
        _totalDoctors        = totalDoctors;
        _pendingVerif        = pendingVerif;
        _onlineNow           = onlineNow;
        _recentVerifRequests = recentRes.cast<Map<String, dynamic>>();
        _statsLoading        = false;
      });
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  static const List<({_AdminSection section, IconData icon, String label})>
      _kItems = <({_AdminSection section, IconData icon, String label})>[
    (section: _AdminSection.dashboard,     icon: Icons.dashboard_outlined,       label: 'الرئيسية'),
    (section: _AdminSection.verification,  icon: Icons.verified_user_outlined,   label: 'التوثيق'),
    (section: _AdminSection.clinics,       icon: Icons.local_hospital_outlined,  label: 'العيادات'),
  ];

  Widget _buildBody() {
    return switch (_section) {
      _AdminSection.dashboard    => _buildDashboard(),
      _AdminSection.verification => const VerificationReviewScreen(),
      _AdminSection.clinics      => const ClinicsManagementScreen(),
    };
  }

  // ── Dashboard tab ──────────────────────────────────────────────────────────

  Widget _buildDashboard() {
    if (_statsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _buildDashHeader(),
          const SizedBox(height: 20),
          _buildStatsRow(),
          const SizedBox(height: 24),
          _buildRecentSection(),
        ],
      ),
    );
  }

  Widget _buildDashHeader() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('الرئيسية',
                  style: GoogleFonts.cairo(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1D3557))),
              Text('نظرة عامة على حالة التطبيق',
                  style: GoogleFonts.cairo(
                      fontSize: 13, color: const Color(0xFF607D8B))),
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
          label: 'إجمالي الأطباء المسجلين',
          value: _totalDoctors.toString(),
          icon:  Icons.people_outline,
          color: const Color(0xFF42A5F5),
        ),
        _StatCard(
          label: 'طلبات التوثيق المعلقة',
          value: _pendingVerif.toString(),
          icon:  Icons.pending_actions_outlined,
          color: const Color(0xFFF9A825),
        ),
        _StatCard(
          label: 'العيادات المتاحة الآن',
          value: _onlineNow.toString(),
          icon:  Icons.circle,
          color: const Color(0xFF388E3C),
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
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1D3557))),
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: const Color(0xFF1D3557)),
                          ),
                          Text(date,
                              style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: const Color(0xFF90A4AE))),
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
      VerificationStatus.pending  => ('معلّق',  const Color(0xFFF9A825), const Color(0xFFFFF8E1)),
      VerificationStatus.approved => ('مقبول',  const Color(0xFF388E3C), const Color(0xFFE8F5E9)),
      VerificationStatus.rejected => ('مرفوض',  const Color(0xFFC62828), const Color(0xFFFFEBEE)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: GoogleFonts.cairo(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }

  // ── Shell layout ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF1D3557),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF42A5F5)),
        ),
      );
    }

    final bool wide = MediaQuery.of(context).size.width >= 800;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        appBar: wide
            ? null
            : AppBar(
                backgroundColor: const Color(0xFF1D3557),
                foregroundColor: Colors.white,
                centerTitle: true,
                title: Text(
                  'لوحة الإدارة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                ),
              ),
        drawer: wide ? null : _buildDrawer(),
        body: wide
            ? Row(
                children: <Widget>[
                  _buildSidebar(),
                  Expanded(child: _buildBody()),
                ],
              )
            : _buildBody(),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      color: const Color(0xFF1D3557),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.admin_panel_settings,
                    color: Color(0xFF42A5F5), size: 32),
                const SizedBox(height: 8),
                Text(
                  'المدار الطبي',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'لوحة الإدارة',
                  style: GoogleFonts.cairo(
                      color: const Color(0xFF90A4AE), fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2C4A6B), height: 1),
          const SizedBox(height: 8),
          ..._kItems.map((item) => _SidebarItem(
                label: item.label,
                icon: item.icon,
                selected: _section == item.section,
                onTap: () => setState(() => _section = item.section),
              )),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.exit_to_app,
                  color: Color(0xFF90A4AE), size: 18),
              label: Text(
                'خروج',
                style: GoogleFonts.cairo(
                    color: const Color(0xFF90A4AE), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: const Color(0xFF1D3557),
        child: Column(
          children: <Widget>[
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1D3557)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  const Icon(Icons.admin_panel_settings,
                      color: Color(0xFF42A5F5), size: 28),
                  const SizedBox(height: 6),
                  Text('المدار الطبي',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text('لوحة الإدارة',
                      style: GoogleFonts.cairo(
                          color: const Color(0xFF90A4AE), fontSize: 12)),
                ],
              ),
            ),
            ..._kItems.map((item) => ListTile(
                  leading: Icon(item.icon,
                      color: _section == item.section
                          ? const Color(0xFF42A5F5)
                          : const Color(0xFF90A4AE)),
                  title: Text(item.label,
                      style: GoogleFonts.cairo(
                          color: _section == item.section
                              ? Colors.white
                              : const Color(0xFF90A4AE))),
                  selected: _section == item.section,
                  onTap: () {
                    setState(() => _section = item.section);
                    Navigator.of(context).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ── Private helpers ──────────────────────────────────────────────────────────

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
      width: 10,
      height: 10,
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
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1D3557))),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: const Color(0xFF607D8B),
                  height: 1.4)),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF42A5F5).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF42A5F5).withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon,
                size: 18,
                color: selected
                    ? const Color(0xFF42A5F5)
                    : const Color(0xFF90A4AE)),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? Colors.white : const Color(0xFF90A4AE),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
