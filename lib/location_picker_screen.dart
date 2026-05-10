import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'services/forward_geocode_service.dart';
import 'services/location_permission_service.dart';
import 'services/reverse_geocode_service.dart';

/// Result of picking a point on the map (or manual entry fallback on web).
class LocationPickResult {
  const LocationPickResult(
    this.latitude,
    this.longitude, {
    this.addressLine,
  });
  final double latitude;
  final double longitude;
  final String? addressLine;
}

bool _isValidWgs84(double latitude, double longitude) {
  return latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

/// Full-screen Google Maps picker with optional place search (forward geocode).
/// On web, falls back to manual lat/lng fields (no Maps SDK in this build).
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.title,
  });

  final double initialLatitude;
  final double initialLongitude;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _position;
  GoogleMapController? _controller;
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();
  final TextEditingController _searchQueryCtrl = TextEditingController();
  Timer? _geoDebounce;
  String? _addressLine;
  bool _geoLoading = false;
  bool _searchBusy = false;
  bool _myLocationBusy = false;
  double? _userBiasLat;
  double? _userBiasLng;

  @override
  void initState() {
    super.initState();
    _position = LatLng(widget.initialLatitude, widget.initialLongitude);
    _latCtrl.text = _position.latitude.toStringAsFixed(6);
    _lngCtrl.text = _position.longitude.toStringAsFixed(6);
    _scheduleReverseGeocode();
    unawaited(_loadUserBiasIfPermitted());
  }

  /// Silently fetches the user's current position (without prompting) so that
  /// [_runPlaceSearch] can bias results. Falls through quietly on denial/error.
  Future<void> _loadUserBiasIfPermitted() async {
    try {
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) {
        return;
      }
      setState(() {
        _userBiasLat = p.latitude;
        _userBiasLng = p.longitude;
      });
    } catch (_) {
      // Intentional silent: the search still works globally without bias.
    }
  }

  @override
  void dispose() {
    _geoDebounce?.cancel();
    _controller?.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _searchQueryCtrl.dispose();
    super.dispose();
  }

  void _scheduleReverseGeocode() {
    _geoDebounce?.cancel();
    _geoDebounce = Timer(const Duration(milliseconds: 550), () async {
      if (!mounted) {
        return;
      }
      setState(() {
        _geoLoading = true;
        _addressLine = null;
      });
      final String? line = await ReverseGeocodeService.lookupAddress(
        _position.latitude,
        _position.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _geoLoading = false;
        _addressLine = line;
      });
    });
  }

  void _applyMapPosition(LatLng p) {
    setState(() {
      _position = p;
      _latCtrl.text = p.latitude.toStringAsFixed(6);
      _lngCtrl.text = p.longitude.toStringAsFixed(6);
    });
    _scheduleReverseGeocode();
  }

  void _applyManualFields() {
    final double? la = double.tryParse(_latCtrl.text.replaceAll(',', '.'));
    final double? ln = double.tryParse(_lngCtrl.text.replaceAll(',', '.'));
    if (la == null || ln == null) {
      return;
    }
    if (!_isValidWgs84(la, ln)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'إحداثيات غير صالحة: خط العرض بين −90 و90، خط الطول بين −180 و180.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _position = LatLng(la, ln);
    });
    _controller?.animateCamera(CameraUpdate.newLatLng(_position));
    _scheduleReverseGeocode();
  }

  Future<void> _runPlaceSearch() async {
    FocusScope.of(context).unfocus();
    setState(() => _searchBusy = true);
    // Prefer the user's actual location for biasing; fall back to the current
    // marker position (works inside Iraq even before GPS resolves).
    final double biasLat = _userBiasLat ?? _position.latitude;
    final double biasLng = _userBiasLng ?? _position.longitude;
    final LatLngName? hit = await ForwardGeocodeService.searchFirst(
      _searchQueryCtrl.text,
      biasLatitude: biasLat,
      biasLongitude: biasLng,
    );
    if (!mounted) {
      return;
    }
    setState(() => _searchBusy = false);
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يُعثر على مكان مطابق. جرّب كلمات أخرى.')),
      );
      return;
    }
    setState(() {
      _position = LatLng(hit.latitude, hit.longitude);
      _latCtrl.text = hit.latitude.toStringAsFixed(6);
      _lngCtrl.text = hit.longitude.toStringAsFixed(6);
    });
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(_position, 16),
    );
    _scheduleReverseGeocode();
  }

  void _popWithResult() {
    if (!_isValidWgs84(_position.latitude, _position.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('إحداثيات غير صالحة. راجع خط العرض وخط الطول.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      LocationPickResult(
        _position.latitude,
        _position.longitude,
        addressLine: _addressLine,
      ),
    );
  }

  Future<void> _centerOnMyLocation() async {
    setState(() => _myLocationBusy = true);
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('خدمة الموقع (GPS) معطّلة. فعّلها من الإعدادات.'),
            action: SnackBarAction(
              label: 'فتح الإعدادات',
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      final bool granted =
          await LocationPermissionService.requestWithRationale(context);
      if (!granted) return;

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw TimeoutException('getCurrentPosition');
        },
      );

      final LatLng next = LatLng(pos.latitude, pos.longitude);
      if (!mounted) {
        return;
      }
      setState(() {
        _position = next;
        _latCtrl.text = next.latitude.toStringAsFixed(6);
        _lngCtrl.text = next.longitude.toStringAsFixed(6);
      });
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(next, 16),
      );
      _scheduleReverseGeocode();
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('انتهت مهلة جلب الموقع. حاول مرة أخرى.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              onPressed: () {
                unawaited(_centerOnMyLocation());
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر جلب الموقع: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              onPressed: () {
                unawaited(_centerOnMyLocation());
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _myLocationBusy = false);
      }
    }
  }

  Widget _buildSearchBar() {
    return Material(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _searchQueryCtrl,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'بحث عن مكان (اسم، شارع، مدينة)',
                  prefixIcon: Icon(Icons.search, size: 22),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _runPlaceSearch(),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'بحث',
              onPressed: _searchBusy ? null : _runPlaceSearch,
              icon: _searchBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          TextButton(
            onPressed: _popWithResult,
            child: const Text('تأكيد'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildSearchBar(),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _position,
                    zoom: 15,
                  ),
                  onMapCreated: (GoogleMapController c) => _controller = c,
                  markers: <Marker>{
                    Marker(
                      markerId: const MarkerId('pick'),
                      position: _position,
                      draggable: true,
                      onDragEnd: (LatLng p) {
                        _applyMapPosition(p);
                      },
                    ),
                  },
                  onTap: (LatLng p) {
                    _applyMapPosition(p);
                  },
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: true,
                ),
                Positioned(
                  right: 12,
                  bottom: 100,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_myLocationBusy)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      FloatingActionButton(
                        heroTag: 'location_picker_my_location',
                        tooltip: 'موقعي',
                        onPressed: _myLocationBusy ? null : _centerOnMyLocation,
                        child: const Text(
                          '📍',
                          style: TextStyle(fontSize: 22),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _latCtrl,
                            decoration: const InputDecoration(
                              labelText: 'latitude',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _applyManualFields(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lngCtrl,
                            decoration: const InputDecoration(
                              labelText: 'longitude',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _applyManualFields(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تطبيق الأرقام',
                          onPressed: _applyManualFields,
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_geoLoading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else if (_addressLine != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _addressLine!,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    FilledButton(
                      onPressed: _popWithResult,
                      child: const Text('حفظ هذا الموقع'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
