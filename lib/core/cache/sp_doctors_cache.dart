// ✅ UPDATED 2026-05-09
// Temporary SharedPreferences-based cache for doctors list.
// Replace with HiveCacheService after adding hive_flutter to pubspec.yaml.
// shared_preferences is already in pubspec.yaml — no new package needed.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpDoctorsCache {
  static const Duration _ttl = Duration(hours: 12);

  static String _key(String gove) => 'doctors_cache_$gove';
  static String _tsKey(String gove) => 'doctors_cache_ts_$gove';

  static Future<void> save(
    String gove,
    List<Map<String, dynamic>> doctors,
  ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String json = jsonEncode(doctors);
      await prefs.setString(_key(gove), json);
      await prefs.setInt(
        _tsKey(gove),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('SpDoctorsCache.save error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>?> load(String gove) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? ts = prefs.getInt(_tsKey(gove));
      if (ts == null) return null;
      final int age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _ttl.inMilliseconds) return null; // expired
      final String? json = prefs.getString(_key(gove));
      if (json == null) return null;
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('SpDoctorsCache.load error: $e');
      return null;
    }
  }

  /// Returns the cache timestamp as a human-readable string, or null if no cache.
  static Future<String?> cacheTimestamp(String gove) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? ts = prefs.getInt(_tsKey(gove));
      if (ts == null) return null;
      final DateTime dt =
          DateTime.fromMillisecondsSinceEpoch(ts, isUtc: false);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String gove) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(gove));
      await prefs.remove(_tsKey(gove));
    } catch (_) {}
  }
}
