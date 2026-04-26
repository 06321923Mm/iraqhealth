// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';

@JS('pwaInstall')
external JSBoolean _jsPwaInstall();

/// Returns true if the native install prompt was shown, false otherwise.
bool triggerPwaInstall() {
  try {
    return _jsPwaInstall().toDart;
  } catch (_) {
    return false;
  }
}
