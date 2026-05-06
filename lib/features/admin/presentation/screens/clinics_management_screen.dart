import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../arabic_search_normalize.dart';
import '../../../../core/components/status_badge.dart';
import '../../../../core/components/verification_badge.dart';
import '../../../../core/config/app_endpoints.dart';
import '../../../../doctor_constants.dart';

class ClinicsManagementScreen extends StatefulWidget {
  const ClinicsManagementScreen({super.key});

  @override
  State<ClinicsManagementScreen> createState() =>
      _ClinicsManagementScreenState();
}

class _ClinicsManagementScreenState extends State<ClinicsManagementScreen> {
  final SupabaseClient _db = Supabase.instance.client;

  static const int _kPageSize = 20;
  int _page     = 0;
  bool _loading = true;
  bool _hasMore = true;

  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  // Filters
  String _searchQuery    = '';
  String? _filterGove;
  String? _filterSpec;
  bool?   _filterVerified;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() { _page = 0; _rows = <Map<String, dynamic>>[]; _hasMore = true; });
    }
    setState(() => _loading = true);

    try {
      var filterQuery = _db
          .from(AppEndpoints.doctors)
          .select('id, name, spec, gove, area, ph, is_verified, current_status, owner_user_id');

      if (_filterGove != null)     filterQuery = filterQuery.eq('gove', _filterGove!);
      if (_filterSpec != null)     filterQuery = filterQuery.eq('spec', _filterSpec!);
      if (_filterVerified != null) filterQuery = filterQuery.eq('is_verified', _filterVerified!);

      final query = filterQuery
          .order('id', ascending: true)
          .range(_page * _kPageSize, (_page + 1) * _kPageSize - 1);

      final List<dynamic> data = await query;
      if (!mounted) return;

      List<Map<String, dynamic>> rows = data.cast<Map<String, dynamic>>();

      // Arabic-normalised client-side search
      if (_searchQuery.trim().isNotEmpty) {
        final String norm = normalizeArabic(_searchQuery.trim().toLowerCase());
        rows = rows.where((Map<String, dynamic> r) {
          final String name = normalizeArabic((r['name'] ?? '').toString().toLowerCase());
          final String spec = normalizeArabic((r['spec'] ?? '').toString().toLowerCase());
          return name.contains(norm) || spec.contains(norm);
        }).toList();
      }

      setState(() {
        _rows.addAll(rows);
        _hasMore = data.length == _kPageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _nextPage() {
    if (!_hasMore) return;
    _page++;
    _load();
  }

  void _prevPage() {
    if (_page == 0) return;
    _page--;
    _load(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(),
            const SizedBox(height: 12),
            _buildFilters(),
            const SizedBox(height: 12),
            Expanded(
              child: _loading && _rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildTable(),
            ),
            _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text('إدارة العيادات',
        style: GoogleFonts.cairo(
            fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1D3557)));
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        // Search
        SizedBox(
          width: 220,
          height: 40,
          child: TextField(
            controller: _searchCtrl,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو التخصص...',
              hintStyle: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF90A4AE)),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF90A4AE)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: GoogleFonts.cairo(fontSize: 13),
            onChanged: (String v) {
              setState(() => _searchQuery = v);
              _load(reset: true);
            },
          ),
        ),
        // Governorate filter
        DropdownButton<String>(
          value: _filterGove,
          hint: Text('المحافظة', style: GoogleFonts.cairo(fontSize: 12)),
          style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF1D3557)),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: null,
              child: Text('الكل', style: GoogleFonts.cairo()),
            ),
            ...kGovernorates.map((String g) => DropdownMenuItem<String>(
                  value: g, child: Text(g, style: GoogleFonts.cairo()),
                )),
          ],
          onChanged: (String? v) {
            setState(() => _filterGove = v);
            _load(reset: true);
          },
        ),
        // Verification filter
        DropdownButton<bool>(
          value: _filterVerified,
          hint: Text('الحالة', style: GoogleFonts.cairo(fontSize: 12)),
          style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF1D3557)),
          items: <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: null,  child: Text('الكل', style: GoogleFonts.cairo())),
            DropdownMenuItem<bool>(value: true,  child: Text('موثّق', style: GoogleFonts.cairo())),
            DropdownMenuItem<bool>(value: false, child: Text('غير موثّق', style: GoogleFonts.cairo())),
          ],
          onChanged: (bool? v) {
            setState(() => _filterVerified = v);
            _load(reset: true);
          },
        ),
        // Refresh
        IconButton(
          onPressed: () => _load(reset: true),
          icon: const Icon(Icons.refresh, color: Color(0xFF42A5F5)),
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  Widget _buildTable() {
    if (_rows.isEmpty && !_loading) {
      return Center(
          child: Text('لا توجد نتائج.', style: GoogleFonts.cairo(color: const Color(0xFF90A4AE))));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FBFF)),
            headingTextStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF607D8B)),
            dataTextStyle: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF1D3557)),
            columnSpacing: 20,
            horizontalMargin: 16,
            columns: const <DataColumn>[
              DataColumn(label: Text('#')),
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('التخصص')),
              DataColumn(label: Text('المنطقة')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('موثّق')),
            ],
            rows: _rows.asMap().entries.map((MapEntry<int, Map<String, dynamic>> entry) {
              final Map<String, dynamic> row = entry.value;
              final bool isVerified = (row['is_verified'] as bool?) ?? false;
              final DoctorStatus status = DoctorStatusX.fromString(row['current_status'] as String?);

              return DataRow(
                cells: <DataCell>[
                  DataCell(Text((row['id'] ?? '').toString(),
                      style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF90A4AE)))),
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Text(
                        (row['name'] ?? '—').toString(),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  DataCell(Text(
                    _truncate((row['spec'] ?? '—').toString(), 20),
                    style: GoogleFonts.cairo(fontSize: 12),
                  )),
                  DataCell(Text(
                    '${(row['area'] ?? '').toString()} - ${(row['gove'] ?? '').toString()}',
                    style: GoogleFonts.cairo(fontSize: 11),
                  )),
                  DataCell(isVerified ? StatusBadge(status: status) : const SizedBox.shrink()),
                  DataCell(isVerified ? const VerificationBadge() : const SizedBox.shrink()),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            onPressed: _page > 0 ? _prevPage : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'السابق',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'الصفحة ${_page + 1}',
              style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF607D8B)),
            ),
          ),
          IconButton(
            onPressed: _hasMore ? _nextPage : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'التالي',
          ),
        ],
      ),
    );
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;
}
