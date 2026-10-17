// Firebase options for the project "daily-expense-buddy-e0980": Android (from
// android/app/google-services.json) and Web (from
// `firebase apps:sdkconfig web`). Re-generate with `flutterfire configure`
// when adding iOS.
//
// These are public client identifiers, not secrets. Access to data is
// controlled by Firebase Authentication and firestore.rules.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is only configured for Android so far. Register the '
          'platform in the Firebase console and run `flutterfire configure`.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD1fI0DLySG2jQkrsW5nNg4o0n2pVG4ys8',
    appId: '1:667205827958:web:d74161258b1058152e0e57',
    messagingSenderId: '667205827958',
    projectId: 'daily-expense-buddy-e0980',
    authDomain: 'daily-expense-buddy-e0980.firebaseapp.com',
    storageBucket: 'daily-expense-buddy-e0980.firebasestorage.app',
    measurementId: 'G-2HD6BBX75C',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAQYqMQFCe768Z16uSyW2OcnzFYHE3TvDc',
    appId: '1:667205827958:android:b92a07173f5005a72e0e57',
    messagingSenderId: '667205827958',
    projectId: 'daily-expense-buddy-e0980',
    storageBucket: 'daily-expense-buddy-e0980.firebasestorage.app',
  );
}
