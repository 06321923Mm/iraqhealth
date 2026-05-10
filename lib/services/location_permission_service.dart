import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/location_rationale_sheet.dart';

class LocationPermissionService {
  static const String _shownKey = 'location_rationale_shown';

  /// Requests location permission, showing a rationale sheet the first time.
  ///
  /// Returns true if permission is (or becomes) granted.
  static Future<bool> requestWithRationale(BuildContext context) async {
    // 1. Already granted — nothing to do.
    final PermissionStatus current = await Permission.location.status;
    if (current.isGranted) return true;

    // 2. Permanently denied — open system settings, can't request in-app.
    if (current.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // 3. First time: show the rationale sheet (handles the request itself).
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool alreadyShown = prefs.getBool(_shownKey) ?? false;

    if (!alreadyShown) {
      await prefs.setBool(_shownKey, true);
      if (!context.mounted) return false;
      return LocationRationaleSheet.show(context);
    }

    // 4. Rationale was shown before — go straight to the OS dialog.
    final PermissionStatus result = await Permission.location.request();
    return result.isGranted;
  }
}
