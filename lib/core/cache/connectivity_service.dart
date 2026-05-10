// ✅ UPDATED 2026-05-09
// Uses connectivity_plus (already in pubspec.yaml — no new package needed).

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static Future<bool> isOnline() async {
    final List<ConnectivityResult> results =
        await Connectivity().checkConnectivity();
    return results.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
  }

  static Stream<bool> onlineStream() {
    return Connectivity().onConnectivityChanged.map(
      (List<ConnectivityResult> results) => results.any(
        (ConnectivityResult r) => r != ConnectivityResult.none,
      ),
    );
  }
}
