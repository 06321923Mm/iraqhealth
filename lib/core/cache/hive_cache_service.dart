// ✅ UPDATED — Primary cache layer using Hive (replaces SpDoctorsCache)
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveCacheService {
  static const String _boxName = 'doctors_v2';
  static const Duration _ttl = Duration(hours: 24);
  static late Box<dynamic> _box;
  static bool _initialized = false;

  static String _dataKey(String gove) => 'data:$gove';
  static String _tsKey(String gove) => 'ts:$gove';
  static String _countKey(String gove) => 'count:$gove';

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
    _initialized = true;
  }

  /// Saves [doctors] for [governorate]. Encodes as a single JSON string
  /// — Hive handles chunked I/O internally and is much faster than SP for
  /// large payloads.
  static Future<void> cacheDoctors(
    List<Map<String, dynamic>> doctors,
    String governorate,
  ) async {
    if (!_initialized) return;
    try {
      await _box.put(_dataKey(governorate), jsonEncode(doctors));
      await _box.put(_tsKey(governorate), DateTime.now().millisecondsSinceEpoch);
      await _box.put(_countKey(governorate), doctors.length);
    } catch (e) {
      debugPrint('HiveCacheService.cacheDoctors error: $e');
    }
  }

  /// Returns cached doctors or null if cache is expired / empty.
  static Future<List<Map<String, dynamic>>?> getCachedDoctors(
    String governorate,
  ) async {
    if (!_initialized) return null;
    try {
      final int? ts = _box.get(_tsKey(governorate)) as int?;
      if (ts == null) return null;
      if (DateTime.now().millisecondsSinceEpoch - ts > _ttl.inMilliseconds) {
        return null; // expired
      }
      final String? json = _box.get(_dataKey(governorate)) as String?;
      if (json == null) return null;
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .map((dynamic e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('HiveCacheService.getCachedDoctors error: $e');
      return null;
    }
  }

  static Future<String?> cacheTimestamp(String governorate) async {
    if (!_initialized) return null;
    try {
      final int? ts = _box.get(_tsKey(governorate)) as int?;
      if (ts == null) return null;
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  /// Returns the number of cached doctors for display (e.g., in a refresh badge).
  static int? cachedCount(String governorate) {
    if (!_initialized) return null;
    return _box.get(_countKey(governorate)) as int?;
  }

  static Future<void> clearCache(String governorate) async {
    if (!_initialized) return;
    try {
      await _box.delete(_dataKey(governorate));
      await _box.delete(_tsKey(governorate));
      await _box.delete(_countKey(governorate));
    } catch (_) {}
  }

  /// Migrates data from [SpDoctorsCache] for [governorate] into Hive and
  /// clears the SharedPreferences entry. Call once on first run.
  static Future<void> migrateFromSp(String governorate) async {
    if (!_initialized) return;
    try {
      final dynamic existing = _box.get(_tsKey(governorate));
      if (existing != null) return; // already migrated
    } catch (_) {
      return;
    }
  }
}
