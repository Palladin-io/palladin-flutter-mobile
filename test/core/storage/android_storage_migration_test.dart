import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/storage/biometric_key_storage.dart';
import 'package:mobile_palladin/core/storage/biometric_storage_key_store.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';

import '../../helpers/android_contract_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AndroidContractStorage storage;
  late SecureTokenStorage tokens;
  setUp(() {
    configureDependencies(EnvConfig.local());
    storage = AndroidContractStorage(getIt<FlutterSecureStorage>().aOptions);
    tokens = SecureTokenStorage(storage);
  });
  tearDown(() async {
    await getIt.reset();
  });
  test(
    'biometric marker operations cannot move the active session out of reach',
    () async {
      await tokens.saveTokens(
        accessToken: 'dummy-access',
        refreshToken: 'dummy-refresh',
        userId: 'dummy-account',
        isOnboarded: true,
      );
      await storage.write(
        key: BiometricKeyStorage.legacyRawKey,
        value: 'dummy-legacy-key',
      );
      await storage.write(
        key: BiometricKeyStorage.enrolledMarkerKey,
        value: '1',
        aOptions: BiometricKeyStorage.androidOptions,
      );
      final biometrics = BiometricStorageKeyStore(markerStorage: storage);
      expect(await biometrics.isEnrolled(), isTrue);
      await biometrics.purgeLegacyRawKey();
      await BiometricKeyStorage.clear(storage);
      expect(await storage.read(key: BiometricKeyStorage.legacyRawKey), isNull);
      expect(await biometrics.isEnrolled(), isFalse);
      expect(await tokens.userId, 'dummy-account');
      expect(await tokens.accessToken, 'dummy-access');
      expect(await tokens.refreshToken, 'dummy-refresh');
      expect(await tokens.isOnboarded, isTrue);
    },
  );
  test(
    'startup reads preserve and migrate an existing legacy session',
    () async {
      storage.legacy.addAll({
        'user_id': 'old-account',
        'access_token': 'old-access',
        'refresh_token': 'old-refresh',
        'is_onboarded': 'true',
      });
      expect(await tokens.userId, 'old-account');
      expect(storage.encrypted['user_id'], 'old-account');
      expect(storage.legacy, isEmpty);
      expect(await tokens.refreshToken, 'old-refresh');
    },
  );
}
