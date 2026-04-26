import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase is not configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBbmjltFzB7SwuAEzTmQ-mr6EjPzqje8aw',
    appId: '1:63970501606:android:3132dbae5437c3a750ec27',
    messagingSenderId: '63970501606',
    projectId: 'iraqhealth-b08f6',
    storageBucket: 'iraqhealth-b08f6.firebasestorage.app',
  );
}
