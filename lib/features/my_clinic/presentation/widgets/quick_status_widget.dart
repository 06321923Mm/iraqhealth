import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/components/status_badge.dart';
import '../../../../core/config/app_endpoints.dart';

class QuickStatusWidget extends StatefulWidget {
  const QuickStatusWidget({
    super.key,
    required this.doctorId,
    required this.initialStatus,
    this.initialMessage,
    this.initialExpiresAt,
  });

  final int doctorId;
  final DoctorStatus initialStatus;
  final String? initialMessage;
  final DateTime? initialExpiresAt;

  @override
  State<QuickStatusWidget> createState() => _QuickStatusWidgetState();
}

class _QuickStatusWidgetState extends State<QuickStatusWidget> {
  late DoctorStatus _status;
  final TextEditingController _msgCtrl = TextEditingController();
  int _selectedExpiry = 0;
  bool _saving = false;
  DateTime? _lastUpdated;

  /// Realtime subscription scoped to this doctor only — avoids unnecessary
  /// data/battery use that an unfiltered .stream() would cause.
  StreamSubscription<List<Map<String, dynamic>>>? _statusSubscription;

  static const List<({int? hours, String label, bool endOfDay})>
      _expiryOptions = <({int? hours, String label, bool endOfDay})>[
    (hours: null,  label: 'بدون انتهاء',  endOfDay: false),
    (hours: 1,     label: 'ساعة واحدة',   endOfDay: false),
    (hours: 2,     label: 'ساعتان',        endOfDay: false),
    (hours: 4,     label: '٤ ساعات',       endOfDay: false),
    (hours: null,  label: 'نهاية اليوم',  endOfDay: true),
  ];

  @override
  void initState() {
    super.initState();
    _status       = widget.initialStatus;
    _msgCtrl.text = widget.initialMessage ?? '';
    _lastUpdated  = widget.initialExpiresAt;
    _subscribeToStatus();
  }

  void _subscribeToStatus() {
    _statusSubscription?.cancel();
    _statusSubscription = Supabase.instance.client
        .from(AppEndpoints.doctors)
        .stream(primaryKey: <String>['id'])
        .eq('id', widget.doctorId)
        .listen(_onStatusChanged, onError: (_) {});
  }

  void _onStatusChanged(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty || _saving) return;
    final Map<String, dynamic> row = rows.first;
    final DoctorStatus status = DoctorStatusX.fromString(
      row['current_status']?.toString(),
    );
    final String? message = row['status_message']?.toString();
    final dynamic rawUpdated = row['last_status_update'] ?? row['updated_at'];
    DateTime? lastUpdated;
    if (rawUpdated != null) {
      lastUpdated = DateTime.tryParse(rawUpdated.toString())?.toLocal();
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      if (message != null && _msgCtrl.text != message) {
        _msgCtrl.text = message;
      }
      if (lastUpdated != null) {
        _lastUpdated = lastUpdated;
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final DateTime now = DateTime.now().toUtc();
      final ({int? hours, String label, bool endOfDay}) expiry =
          _expiryOptions[_selectedExpiry];

      String? expiresAtIso;
      if (expiry.endOfDay) {
        expiresAtIso =
            DateTime.utc(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
      } else if (expiry.hours != null) {
        expiresAtIso = now.add(Duration(hours: expiry.hours!)).toIso8601String();
      }

      await Supabase.instance.client
          .from(AppEndpoints.doctors)
          .update(<String, dynamic>{
            'current_status':    _status.name,
            'status_message':    _msgCtrl.text.trim().isNotEmpty
                ? _msgCtrl.text.trim()
                : null,
            'status_expires_at': expiresAtIso,
          })
          .eq('id', widget.doctorId);

      if (!mounted) return;
      setState(() {
        _lastUpdated = DateTime.now();
        _saving      = false;
      });
      _snack('تم تحديث الحالة بنجاح.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('تعذّر التحديث: ${e.toString()}');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.circle_notifications_outlined,
                  color: Color(0xFF42A5F5), size: 20),
              const SizedBox(width: 8),
              Text(
                'حالة الإتاحة',
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1D3557),
                ),
              ),
              const Spacer(),
              StatusBadge(status: _status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: DoctorStatus.values.map((DoctorStatus s) {
              final bool selected = _status == s;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _StatusToggle(
                    label: s.arabicLabel,
                    selected: selected,
                    color: s.color,
                    bgColor: s.bgColor,
                    onTap: () => setState(() => _status = s),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _msgCtrl,
            textDirection: TextDirection.rtl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'رسالة للمرضى (اختياري)',
              hintStyle: GoogleFonts.cairo(
                  color: const Color(0xFFB0BEC5), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF7FBFF),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Color(0xFF42A5F5), width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style:
                GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF1D3557)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedExpiry,
            decoration: InputDecoration(
              labelText: 'مدة الانتهاء',
              labelStyle: GoogleFonts.cairo(
                  fontSize: 13, color: const Color(0xFF607D8B)),
              filled: true,
              fillColor: const Color(0xFFF7FBFF),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCFD8DC))),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style:
                GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF1D3557)),
            items: List<DropdownMenuItem<int>>.generate(
              _expiryOptions.length,
              (int i) => DropdownMenuItem<int>(
                value: i,
                child: Text(_expiryOptions[i].label,
                    style: GoogleFonts.cairo(fontSize: 13)),
              ),
            ),
            onChanged: (int? v) {
              if (v != null) setState(() => _selectedExpiry = v);
            },
          ),
          if (_lastUpdated != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'آخر تحديث: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
              style: GoogleFonts.cairo(
                  fontSize: 11, color: const Color(0xFF90A4AE)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, size: 18),
              label: Text(
                _saving ? 'جارٍ التحديث...' : 'تحديث الحالة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF42A5F5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({
    required this.label,
    required this.selected,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? bgColor : const Color(0xFFF7FBFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0xFFCFD8DC),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : const Color(0xFF607D8B),
            ),
          ),
        ),
      ),
    );
  }
}
