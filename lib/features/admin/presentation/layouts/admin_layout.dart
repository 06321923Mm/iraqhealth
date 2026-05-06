import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin_dashboard_screen.dart';
import '../screens/clinics_management_screen.dart';
import '../screens/verification_review_screen.dart';

enum _AdminSection { dashboard, verification, clinics }

/// Entry point for the new admin hub.
/// Guards access by checking `app_metadata.role == "admin"` on the current
/// Supabase user. Falls back to an access-denied screen.
class AdminHubPage extends StatefulWidget {
  const AdminHubPage({super.key});

  @override
  State<AdminHubPage> createState() => _AdminHubPageState();
}

/// Returns true when the currently signed-in Supabase user carries
/// `app_metadata.role = "admin"`. Requires no extra network call —
/// the JWT payload already contains app_metadata.
bool _isAdminUser() {
  final User? user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;
  // app_metadata is sourced from raw_app_meta_data in the JWT.
  final dynamic role = user.appMetadata['role'];
  return role == 'admin';
}

class _AdminHubPageState extends State<AdminHubPage> {
  _AdminSection _section = _AdminSection.dashboard;

  static const List<({_AdminSection section, IconData icon, String label})>
      _kItems = <({_AdminSection section, IconData icon, String label})>[
    (section: _AdminSection.dashboard,     icon: Icons.dashboard_outlined,       label: 'الرئيسية'),
    (section: _AdminSection.verification,  icon: Icons.verified_user_outlined,   label: 'التوثيق'),
    (section: _AdminSection.clinics,       icon: Icons.local_hospital_outlined,  label: 'العيادات'),
  ];

  Widget _buildBody() {
    return switch (_section) {
      _AdminSection.dashboard    => const AdminDashboardScreen(),
      _AdminSection.verification => const VerificationReviewScreen(),
      _AdminSection.clinics      => const ClinicsManagementScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Guard: only users with app_metadata.role = "admin" may enter.
    if (!_isAdminUser()) {
      return _AccessDeniedPage();
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
                const Icon(Icons.admin_panel_settings, color: Color(0xFF42A5F5), size: 32),
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
                  style: GoogleFonts.cairo(color: const Color(0xFF90A4AE), fontSize: 12),
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
              icon: const Icon(Icons.exit_to_app, color: Color(0xFF90A4AE), size: 18),
              label: Text(
                'خروج',
                style: GoogleFonts.cairo(color: const Color(0xFF90A4AE), fontSize: 13),
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
                  const Icon(Icons.admin_panel_settings, color: Color(0xFF42A5F5), size: 28),
                  const SizedBox(height: 6),
                  Text('المدار الطبي',
                      style: GoogleFonts.cairo(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('لوحة الإدارة',
                      style: GoogleFonts.cairo(color: const Color(0xFF90A4AE), fontSize: 12)),
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
                          color: _section == item.section ? Colors.white : const Color(0xFF90A4AE))),
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
          color: selected ? const Color(0xFF42A5F5).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF42A5F5).withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: selected ? const Color(0xFF42A5F5) : const Color(0xFF90A4AE)),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? Colors.white : const Color(0xFF90A4AE),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Access-denied screen shown when the user lacks the admin role ─────────────

class _AccessDeniedPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFEBEE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'غير مصرّح بالدخول',
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1D3557),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'هذه الصفحة مخصصة للمشرفين فقط.\n'
                  'يجب أن يحمل حسابك صلاحية "admin" للوصول إلى لوحة الإدارة.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: const Color(0xFF607D8B),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                  label: Text(
                    'العودة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
