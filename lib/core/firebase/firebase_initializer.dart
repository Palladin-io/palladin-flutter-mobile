import 'package:firebase_core/firebase_core.dart';

import '../utils/app_logger.dart';

/// Initializes the Firebase app for the current flavor.
///
/// Configuration is supplied **natively per flavor** — Android reads the
/// per-flavor `google-services.json` under `android/app/src/{flavor}/`,
/// iOS reads the per-flavor `GoogleService-Info.plist`. We therefore call
/// [Firebase.initializeApp] without explicit `options` (no generated
/// `firebase_options.dart`), letting the native default config drive it.
///
/// Returns `false` if initialization fails (e.g. missing native config on
/// a dev machine) so the app can still boot without push support instead
/// of crashing at startup.
class FirebaseInitializer {
  const FirebaseInitializer._();

  static Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      AppLogger.i('Firebase', 'Initialized');
      return true;
    } catch (e) {
      AppLogger.w('Firebase', 'Initialization failed: $e');
      return false;
    }
  }
}
