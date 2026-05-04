import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../app_navigation.dart';
import '../location_picker_screen.dart';

/// Inline interactive Google Map for picking a doctor location within a form
/// page (no dialog/sheet indirection). Tap map or drag marker to set coords;
/// tap "توسيع الخريطة" to open the full [LocationPickerScreen] with search.
///
/// Falls back to numeric lat/lng fields on web (same as [LocationPickerScreen]).
class InlineDoctorLocationPicker extends StatefulWidget {
  const InlineDoctorLocationPicker({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.height = 260,
    this.title = 'موقع العيادة على الخريطة',
  });

  final double? latitude;
  final double? longitude;
  final void Function(double latitude, double longitude) onChanged;
  final double height;
  final String title;

  static const double _defaultLat = 30.5039;
  static const double _defaultLng = 47.7806;

  @override
  State<InlineDoctorLocationPicker> createState() =>
      _InlineDoctorLocationPickerState();
}

class _InlineDoctorLocationPickerState
    extends State<InlineDoctorLocationPicker> {
  GoogleMapController? _controller;
  late LatLng _pos;
  bool _myLocationBusy = false;

  @override
  void initState() {
    super.initState();
    _pos = LatLng(
      widget.latitude ?? InlineDoctorLocationPicker._defaultLat,
      widget.longitude ?? InlineDoctorLocationPicker._defaultLng,
    );
  }

  @override
  void didUpdateWidget(covariant InlineDoctorLocationPicker old) {
    super.didUpdateWidget(old);
    if (widget.latitude != old.latitude || widget.longitude != old.longitude) {
      final LatLng next = LatLng(
        widget.latitude ?? InlineDoctorLocationPicker._defaultLat,
        widget.longitude ?? InlineDoctorLocationPicker._defaultLng,
      );
      setState(() => _pos = next);
      _controller?.animateCamera(CameraUpdate.newLatLng(next));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _apply(LatLng p) {
    setState(() => _pos = p);
    widget.onChanged(p.latitude, p.longitude);
  }

  Future<void> _openFullPicker() async {
    final LocationPickResult? picked = await Navigator.of(context)
        .push<LocationPickResult>(
      buildAdaptiveRtlRoute<LocationPickResult>(
        LocationPickerScreen(
          initialLatitude: _pos.latitude,
          initialLongitude: _pos.longitude,
          title: widget.title,
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    final LatLng next = LatLng(picked.latitude, picked.longitude);
    setState(() => _pos = next);
    widget.onChanged(picked.latitude, picked.longitude);
    await _controller?.animateCamera(CameraUpdate.newLatLng(next));
  }

  Future<void> _centerOnMyLocation() async {
    if (kIsWeb) {
      return;
    }
    setState(() => _myLocationBusy = true);
    try {
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خدمة الموقع معطّلة.')),
          );
        }
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('إذن الموقع مرفوض.')),
          );
        }
        return;
      }
      final Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) {
        return;
      }
      final LatLng next = LatLng(p.latitude, p.longitude);
      _apply(next);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(next, 16),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر جلب الموقع: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _myLocationBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildManualFieldsFallback();
    }
    final bool has = widget.latitude != null && widget.longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          has
              ? '${widget.latitude!.toStringAsFixed(6)}, ${widget.longitude!.toStringAsFixed(6)}'
              : 'اضغط على الخريطة لتحديد الموقع، أو اسحب العلامة.',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            color: has ? const Color(0xFF334155) : const Color(0xFF94A3B8),
            fontWeight: has ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: <Widget>[
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _pos,
                    zoom: 15,
                  ),
                  onMapCreated: (GoogleMapController c) => _controller = c,
                  markers: <Marker>{
                    Marker(
                      markerId: const MarkerId('doctor'),
                      position: _pos,
                      draggable: true,
                      onDragEnd: _apply,
                    ),
                  },
                  onTap: _apply,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: true,
                  gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FloatingActionButton.small(
                        heroTag: 'inline_picker_my_loc',
                        tooltip: 'موقعي',
                        onPressed:
                            _myLocationBusy ? null : _centerOnMyLocation,
                        child: _myLocationBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location, size: 20),
                      ),
                      const SizedBox(height: 6),
                      FloatingActionButton.small(
                        heroTag: 'inline_picker_expand',
                        tooltip: 'توسيع الخريطة والبحث',
                        onPressed: _openFullPicker,
                        child: const Icon(Icons.open_in_full, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _openFullPicker,
          icon: const Icon(Icons.search, size: 18),
          label: const Text('البحث عن مكان في خرائط Google'),
        ),
      ],
    );
  }

  Widget _buildManualFieldsFallback() {
    final TextEditingController laCtrl = TextEditingController(
      text: widget.latitude?.toStringAsFixed(6) ?? '',
    );
    final TextEditingController lnCtrl = TextEditingController(
      text: widget.longitude?.toStringAsFixed(6) ?? '',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: laCtrl,
          decoration: const InputDecoration(
            labelText: 'خط العرض',
            border: OutlineInputBorder(),
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (String _) {
            final double? la = double.tryParse(laCtrl.text);
            final double? ln = double.tryParse(lnCtrl.text);
            if (la != null && ln != null) {
              widget.onChanged(la, ln);
            }
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: lnCtrl,
          decoration: const InputDecoration(
            labelText: 'خط الطول',
            border: OutlineInputBorder(),
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (String _) {
            final double? la = double.tryParse(laCtrl.text);
            final double? ln = double.tryParse(lnCtrl.text);
            if (la != null && ln != null) {
              widget.onChanged(la, ln);
            }
          },
        ),
      ],
    );
  }
}
