import 'dart:typed_data';

import '../utils/app_logger.dart';
import 'biometric_key_store.dart';

/// Optional enrollment shared by password login and password unlock.
Future<void> enrollBiometricKeyIfAvailable({
  required BiometricKeyStore keyStore,
  required Uint8List masterKey,
  required BiometricPromptCopy copy,
  required int generation,
  required bool Function() isCanceled,
}) async {
  try {
    await keyStore.purgeLegacyRawKey();
    if (isCanceled() || await keyStore.isEnrolled()) return;
    if (isCanceled() || !await keyStore.canStore()) return;
    if (isCanceled() || generation != keyStore.generation) return;
    await keyStore.enroll(masterKey, copy, expectedGeneration: generation);
  } catch (error) {
    // Declining biometrics must never reject a valid password login/unlock.
    AppLogger.w('BiometricKey', 'Enrollment skipped: ${error.runtimeType}');
  }
}
