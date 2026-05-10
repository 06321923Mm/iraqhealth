// ✅ UPDATED 2026-05-09
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class HiveCacheService {
  static const String _boxName = 'doctors_cache';
  static const Duration _cacheTtl = Duration(hours: 24);
  static late Box<dynamic> _box;

  static String _dataKey(String gove) => 'data_$gove';
  static String _tsKey(String gove) => 'ts_$gove';

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  static Future<void> cacheDoctors(
    List<Map<String, dynamic>> doctors,
    String governorate,
  ) async {
    try {
      await _box.put(_dataKey(governorate), jsonEncode(doctors));
      await _box.put(
        _tsKey(governorate),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('HiveCacheService.cacheDoctors error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>?> getCachedDoctors(
    String governorate,
  ) async {
    try {
      final int? ts = _box.get(_tsKey(governorate)) as int?;
      if (ts == null) return null;
      if (DateTime.now().millisecondsSinceEpoch - ts >
          _cacheTtl.inMilliseconds) {
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
    try {
      final int? ts = _box.get(_tsKey(governorate)) as int?;
      if (ts == null) return null;
      final DateTime dt =
          DateTime.fromMillisecondsSinceEpoch(ts, isUtc: false);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCache(String governorate) async {
    try {
      await _box.delete(_dataKey(governorate));
      await _box.delete(_tsKey(governorate));
    } catch (_) {}
  }
}
