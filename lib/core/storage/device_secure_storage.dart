import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every Android user of the shared file must use the same backend. Switching
/// per call migrates/removes legacy entries and makes session reads miss them.
const deviceSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
