import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Reverse geocode via OpenStreetMap Nominatim (no Google Geocoding API key).
abstract final class ReverseGeocodeService {
  ReverseGeocodeService._();

  static const String _userAgent = 'AlMadar-IraqHealth/1.0';

  static Future<String?> lookupAddress(double latitude, double longitude) async {
    final Uri uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      <String, String>{
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'format': 'json',
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
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final String? display = decoded['display_name'] as String?;
      return display?.trim().isEmpty ?? true ? null : display!.trim();
    } catch (e, st) {
      debugPrint('[ReverseGeocodeService] $e $st');
      return null;
    }
  }
}
