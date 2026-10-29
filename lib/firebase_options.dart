// File generated for Novels World Firebase configuration.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAVXdqENS8m6yNmxjws9DxZC-wyAy0mdcw',
    appId: '1:705215795092:web:a4731c348c024c8eaf8981',
    messagingSenderId: '705215795092',
    projectId: 'novels-world-cloud-85457',
    authDomain: 'novels-world-cloud-85457.firebaseapp.com',
    storageBucket: 'novels-world-cloud-85457.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDlx9dsrolE_HPJoZoqitlpE9k6SsjqUQY',
    appId: '1:705215795092:android:34e67b0f438fcdacaf8981',
    messagingSenderId: '705215795092',
    projectId: 'novels-world-cloud-85457',
    storageBucket: 'novels-world-cloud-85457.firebasestorage.app',
  );
}
