// File generated with real Firebase options for shelfmark-13968.
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
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAe0kgzIKCYY_27SGeeOiCH41uHrEc7KMY',
    appId: '1:356770181005:android:c08cbd706520bfd6e597c4',
    messagingSenderId: '356770181005',
    projectId: 'shelfmark-13968',
    storageBucket: 'shelfmark-13968.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAe0kgzIKCYY_27SGeeOiCH41uHrEc7KMY',
    appId: '1:356770181005:ios:c08cbd706520bfd6e597c4',
    messagingSenderId: '356770181005',
    projectId: 'shelfmark-13968',
    storageBucket: 'shelfmark-13968.firebasestorage.app',
    iosBundleId: 'com.faysarukattil.shelfmark',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAe0kgzIKCYY_27SGeeOiCH41uHrEc7KMY',
    appId: '1:356770181005:ios:c08cbd706520bfd6e597c4',
    messagingSenderId: '356770181005',
    projectId: 'shelfmark-13968',
    storageBucket: 'shelfmark-13968.firebasestorage.app',
    iosBundleId: 'com.faysarukattil.shelfmark',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAe0kgzIKCYY_27SGeeOiCH41uHrEc7KMY',
    appId: '1:356770181005:web:c08cbd706520bfd6e597c4',
    messagingSenderId: '356770181005',
    projectId: 'shelfmark-13968',
    authDomain: 'shelfmark-13968.firebaseapp.com',
    storageBucket: 'shelfmark-13968.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAe0kgzIKCYY_27SGeeOiCH41uHrEc7KMY',
    appId: '1:356770181005:web:c08cbd706520bfd6e597c4',
    messagingSenderId: '356770181005',
    projectId: 'shelfmark-13968',
    authDomain: 'shelfmark-13968.firebaseapp.com',
    storageBucket: 'shelfmark-13968.firebasestorage.app',
  );
}
