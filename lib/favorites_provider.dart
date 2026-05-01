import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مفضلات الأطباء محلياً عبر [SharedPreferences] (ترتيب الحفظ يُحترم في العرض).
class FavoritesProvider extends ChangeNotifier {
  static const String _storageKey = 'favorite_doctor_ids_v1';

  final List<int> _orderedIds = <int>[];

  List<int> get orderedFavoriteIds => List<int>.unmodifiable(_orderedIds);

  bool isFavorite(int doctorId) => _orderedIds.contains(doctorId);

  FavoritesProvider() {
    unawaited(loadPrefs());
  }

  Future<void> loadPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? raw = prefs.getStringList(_storageKey);
      _orderedIds.clear();
      if (raw != null) {
        for (final String s in raw) {
          final int? id = int.tryParse(s);
          if (id != null && id > 0 && !_orderedIds.contains(id)) {
            _orderedIds.add(id);
          }
        }
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('FavoritesProvider.loadPrefs: $e\n$st');
    }
  }

  Future<void> toggle(int doctorId) async {
    if (doctorId <= 0) {
      return;
    }
    if (_orderedIds.contains(doctorId)) {
      _orderedIds.remove(doctorId);
    } else {
      _orderedIds.insert(0, doctorId);
    }
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _storageKey,
        _orderedIds.map((int e) => e.toString()).toList(),
      );
    } catch (e, st) {
      debugPrint('FavoritesProvider.toggle save: $e\n$st');
    }
  }

  Future<void> remove(int doctorId) async {
    if (!_orderedIds.remove(doctorId)) {
      return;
    }
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _storageKey,
        _orderedIds.map((int e) => e.toString()).toList(),
      );
    } catch (e, st) {
      debugPrint('FavoritesProvider.remove: $e\n$st');
    }
  }
}
