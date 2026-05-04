import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Forward geocode (place name → lat/lng). Uses Google Geocoding if
/// [String.fromEnvironment] `GOOGLE_MAPS_API_KEY` is set, else OpenStreetMap Nominatim.
abstract final class ForwardGeocodeService {
  ForwardGeocodeService._();

  static const String _userAgent = 'AlMadar-IraqHealth/1.0';
  static const String _googleKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// Biases the search toward [biasLatitude]/[biasLongitude] when provided:
  /// Google Geocoding gets `bounds=...` around the point (~[biasRadiusKm] km);
  /// Nominatim gets `viewbox=...&bounded=1` covering the same area.
  static Future<LatLngName?> searchFirst(
    String query, {
    double? biasLatitude,
    double? biasLongitude,
    double biasRadiusKm = 30,
  }) async {
    final String q = query.trim();
    if (q.length < 2) {
      return null;
    }
    if (_googleKey.isNotEmpty) {
      final LatLngName? g = await _googleGeocode(
        q,
        biasLatitude: biasLatitude,
        biasLongitude: biasLongitude,
        biasRadiusKm: biasRadiusKm,
      );
      if (g != null) {
        return g;
      }
    }
    return _nominatimSearch(
      q,
      biasLatitude: biasLatitude,
      biasLongitude: biasLongitude,
      biasRadiusKm: biasRadiusKm,
    );
  }

  /// Computes a rough bounding box (deg) from a center and radius in km.
  /// Longitude span is scaled by `cos(lat)`; acceptable for small radii.
  static ({double south, double west, double north, double east}) _boundsAround(
    double lat,
    double lng,
    double radiusKm,
  ) {
    const double kmPerDegLat = 110.574;
    final double dLat = radiusKm / kmPerDegLat;
    final double cosLat = _cosDeg(lat);
    final double kmPerDegLng = cosLat.abs() < 1e-6 ? 0.0 : 111.320 * cosLat;
    final double dLng =
        kmPerDegLng.abs() < 1e-6 ? dLat : radiusKm / kmPerDegLng.abs();
    return (
      south: lat - dLat,
      west: lng - dLng,
      north: lat + dLat,
      east: lng + dLng,
    );
  }

  static double _cosDeg(double deg) {
    const double piDeg = 3.141592653589793 / 180.0;
    final double r = deg * piDeg;
    // 6-term Taylor is fine here; we only need ~3 decimal precision for radius.
    final double x2 = r * r;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
  }

  static Future<LatLngName?> _googleGeocode(
    String q, {
    double? biasLatitude,
    double? biasLongitude,
    double biasRadiusKm = 30,
  }) async {
    final Map<String, String> params = <String, String>{
      'address': q,
      'key': _googleKey,
      'language': 'ar',
      'region': 'iq',
    };
    if (biasLatitude != null && biasLongitude != null) {
      final ({double south, double west, double north, double east}) b =
          _boundsAround(biasLatitude, biasLongitude, biasRadiusKm);
      params['bounds'] =
          '${b.south.toStringAsFixed(6)},${b.west.toStringAsFixed(6)}|'
          '${b.north.toStringAsFixed(6)},${b.east.toStringAsFixed(6)}';
    }
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      params,
    );
    try {
      final http.Response res = await http.get(uri);
      if (res.statusCode != 200) {
        return null;
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['status'] != 'OK') {
        return null;
      }
      final Object? results = decoded['results'];
      if (results is! List<dynamic> || results.isEmpty) {
        return null;
      }
      final Object? first = results.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final Object? geo = first['geometry'];
      if (geo is! Map<String, dynamic>) {
        return null;
      }
      final Object? loc = geo['location'];
      if (loc is! Map<String, dynamic>) {
        return null;
      }
      final double? la = (loc['lat'] as num?)?.toDouble();
      final double? ln = (loc['lng'] as num?)?.toDouble();
      if (la == null || ln == null) {
        return null;
      }
      final String name = (first['formatted_address'] as String?)?.trim() ?? q;
      return LatLngName(latitude: la, longitude: ln, displayName: name);
    } catch (e, st) {
      debugPrint('[ForwardGeocodeService] google $e $st');
      return null;
    }
  }

  static Future<LatLngName?> _nominatimSearch(
    String q, {
    double? biasLatitude,
    double? biasLongitude,
    double biasRadiusKm = 30,
  }) async {
    final Map<String, String> params = <String, String>{
      'q': q,
      'format': 'json',
      'limit': '5',
      'accept-language': 'ar,en',
      'countrycodes': 'iq',
    };
    if (biasLatitude != null && biasLongitude != null) {
      final ({double south, double west, double north, double east}) b =
          _boundsAround(biasLatitude, biasLongitude, biasRadiusKm);
      // viewbox expects left,top,right,bottom = west,north,east,south.
      params['viewbox'] =
          '${b.west.toStringAsFixed(6)},${b.north.toStringAsFixed(6)},'
          '${b.east.toStringAsFixed(6)},${b.south.toStringAsFixed(6)}';
      params['bounded'] = '1';
    }
    final Uri uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      params,
    );
    try {
      final http.Response res = await http.get(
        uri,
        headers: <String, String>{'User-Agent': _userAgent},
      );
      if (res.statusCode != 200) {
        return null;
      }
      final Object? decoded = jsonDecode(res.body);
      if (decoded is! List<dynamic> || decoded.isEmpty) {
        return null;
      }
      final Object? first = decoded.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }
      final String? laStr = first['lat'] as String?;
      final String? lnStr = first['lon'] as String?;
      final double? la = double.tryParse(laStr ?? '');
      final double? ln = double.tryParse(lnStr ?? '');
      if (la == null || ln == null) {
        return null;
      }
      final String? dn = first['display_name'] as String?;
      final String name =
          (dn != null && dn.trim().isNotEmpty) ? dn.trim() : q;
      return LatLngName(latitude: la, longitude: ln, displayName: name);
    } catch (e, st) {
      debugPrint('[ForwardGeocodeService] nominatim $e $st');
      return null;
    }
  }
}

class LatLngName {
  const LatLngName({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });
  final double latitude;
  final double longitude;
  final String displayName;
}
