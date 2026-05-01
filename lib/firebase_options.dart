import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
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

  // ══════════════════════════════════════════════════════════════
  // WEB — استبدل القيم أدناه بالقيم الحقيقية من Firebase Console:
  // Project Settings → General → Your Apps → Web App → firebaseConfig

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBI1aJOsgX9bfsT7NNO4vXaP0DospW0JpQ',
    appId: '1:63970501606:web:f13f9990483dee8b50ec27',
    messagingSenderId: '63970501606',
    projectId: 'iraqhealth-b08f6',
    authDomain: 'iraqhealth-b08f6.firebaseapp.com',
    storageBucket: 'iraqhealth-b08f6.firebasestorage.app',
    measurementId: 'G-P3F5TRGJFY',
  );

  // ══════════════════════════════════════════════════════════════

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBbmjltFzB7SwuAEzTmQ-mr6EjPzqje8aw',
    appId: '1:63970501606:android:3132dbae5437c3a750ec27',
    messagingSenderId: '63970501606',
    projectId: 'iraqhealth-b08f6',
    storageBucket: 'iraqhealth-b08f6.firebasestorage.app',
  );

}