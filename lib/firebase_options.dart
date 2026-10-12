// File generated from android/app/google-services.json for the Firebase
// project "daily-expense-buddy-e0980". Re-generate with `flutterfire configure`
// when adding iOS or web apps.
//
// These are public client identifiers, not secrets. Access to data is
// controlled by Firebase Authentication and firestore.rules.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'No Firebase web app is registered yet. In the Firebase console use '
        'Add app -> Web, then run `flutterfire configure`.',
      );
    }
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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAQYqMQFCe768Z16uSyW2OcnzFYHE3TvDc',
    appId: '1:667205827958:android:b92a07173f5005a72e0e57',
    messagingSenderId: '667205827958',
    projectId: 'daily-expense-buddy-e0980',
    storageBucket: 'daily-expense-buddy-e0980.firebasestorage.app',
  );
}
