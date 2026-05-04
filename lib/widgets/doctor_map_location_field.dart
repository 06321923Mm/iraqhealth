import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../location_picker_screen.dart';

/// Reusable "اختيار الموقع" row: opens [LocationPickerScreen], shows coords.
class DoctorMapLocationField extends StatelessWidget {
  const DoctorMapLocationField({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.mapTitle = 'اختيار موقع على الخريطة',
    this.dense = false,
    this.mandatory = true,
    this.allowClear = false,
  });

  final double? latitude;
  final double? longitude;
  final void Function(double? latitude, double? longitude) onChanged;
  final String mapTitle;
  final bool dense;
  final bool mandatory;
  final bool allowClear;

  static const double _defaultMapLat = 30.5039;
  static const double _defaultMapLng = 47.7806;

  Future<void> _openMap(BuildContext context) async {
    final LocationPickResult? picked = await Navigator.of(context)
        .push<LocationPickResult>(
      buildAdaptiveRtlRoute<LocationPickResult>(
        LocationPickerScreen(
          initialLatitude: latitude ?? _defaultMapLat,
          initialLongitude: longitude ?? _defaultMapLng,
          title: mapTitle,
        ),
      ),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    onChanged(picked.latitude, picked.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final bool has = latitude != null && longitude != null;
    final String summary = has
        ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
        : (mandatory
            ? 'يجب تحديد موقع العيادة على خرائط Google'
            : 'لم يُحدد موقع على الخريطة');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (mandatory)
          Padding(
            padding: EdgeInsets.only(bottom: dense ? 4 : 6),
            child: Text(
              'الموقع على الخريطة إلزامي',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: dense ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: has ? const Color(0xFF15803D) : const Color(0xFFB45309),
              ),
            ),
          ),
        Text(
          summary,
          style: TextStyle(
            fontSize: dense ? 12 : 13,
            color: has ? const Color(0xFF334155) : const Color(0xFF94A3B8),
            fontWeight: has ? FontWeight.w600 : FontWeight.w400,
          ),
          textAlign: TextAlign.right,
        ),
        SizedBox(height: dense ? 6 : 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openMap(context),
                icon: const Icon(Icons.map_outlined, size: 20),
                label: const Text('اختيار الموقع'),
              ),
            ),
            if (has && allowClear) ...<Widget>[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'مسح الإحداثيات',
                onPressed: () => onChanged(null, null),
                icon: const Icon(Icons.clear, color: Color(0xFF94A3B8)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
