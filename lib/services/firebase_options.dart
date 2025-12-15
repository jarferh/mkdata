import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Firebase options for the mkdata-39b0f project
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ios;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCRFNTMXGstchWOjcSaOB1Vbnzvq-4t5H0',
    appId: '1:377771923720:android:e494f418d14946e14c34bd',
    messagingSenderId: '377771923720',
    projectId: 'mkdata-39b0f',
    storageBucket: 'mkdata-39b0f.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBvr9GlAPLBCBQYbjBW7BnZ4JqGuzG3bPU',
    appId: '1:377771923720:ios:f61845671c2321914c34bd',
    messagingSenderId: '377771923720',
    projectId: 'mkdata-39b0f',
    storageBucket: 'mkdata-39b0f.firebasestorage.app',
    iosBundleId: 'inc.mk.data',
  );
}
