import 'package:firebase_messaging/firebase_messaging.dart';

import '../../features/notifications/data/services/push_notification_service.dart';
import 'firebase_initializer.dart';

/// Bootstraps Firebase + FCM background handling for any flavor.
///
/// Shared by all `main_*.dart` entry points so the push setup stays in
/// one place. Initializes the Firebase app from the native per-flavor
/// config and registers the top-level background message handler.
///
/// Safe to call even if native Firebase config is missing — Firebase
/// initialization degrades to a no-op (the app boots without push).
Future<void> bootstrapPush() async {
  final initialized = await FirebaseInitializer.initialize();
  if (!initialized) return;

  // Must be registered before runApp so background isolate messages are
  // handled. Token registration / foreground listeners are wired later
  // in ClawVaultApp via the auth lifecycle.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}
