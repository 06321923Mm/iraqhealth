import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Forward geocode (place name → lat/lng). Uses Google Geocoding if
/// [String.fromEnvironment] `GOOGLE_MAPS_API_KEY` is set, else OpenStreetMap Nominatim.
abstract final class ForwardGeocodeService {
  ForwardGeocodeService._();

  static const String _userAgent = 'AlMadar-IraqHealth/1.0';
  static const String _googleKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static Future<LatLngName?> searchFirst(String query) async {
    final String q = query.trim();
    if (q.length < 2) {
      return null;
    }
    if (_googleKey.isNotEmpty) {
      final LatLngName? g = await _googleGeocode(q);
      if (g != null) {
        return g;
      }
    }
    return _nominatimSearch(q);
  }

  static Future<LatLngName?> _googleGeocode(String q) async {
    final Uri uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      <String, String>{
        'address': q,
        'key': _googleKey,
        'language': 'ar',
      },
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

  static Future<LatLngName?> _nominatimSearch(String q) async {
    final Uri uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      <String, String>{
        'q': q,
        'format': 'json',
        'limit': '5',
        'accept-language': 'ar,en',
      },
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
