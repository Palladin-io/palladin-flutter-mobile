import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/change_password_cubit.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';

class Account extends Mock implements AccountRemoteDatasource {}

class Remote extends Mock implements PasswordAuthRemoteDatasource {}

class Crypto extends Mock implements PasswordAuthCryptoService {}

class Keys extends Mock implements BiometricKeyStore {}

void main() {
  test(
    'cleanup failure prevents password mutation and wipes derived keys',
    () async {
      final account = Account();
      final remote = Remote();
      final crypto = Crypto();
      final keys = Keys();
      final material = ChangePasswordMaterial(
        currentAuthCredential: Uint8List(32),
        newAuthCredential: Uint8List(32),
        kdfSalt: Uint8List(16),
        encryptedPrivateKey: Uint8List(72),
        masterKey: Uint8List.fromList(List.filled(32, 7)),
        privateKey: Uint8List.fromList(List.filled(32, 8)),
      );
      when(() => account.getAccount()).thenAnswer(
        (_) async => const AccountResponse(
          userId: '00112233-4455-6677-8899-aabbccddeeff',
          encryptedPrivateKey: 'dummy',
          kdf: IdentityKdfMetadata(
            securityVersion: 1,
            minimumSecurityVersion: 1,
            profileId: IdentityKdfProfile.id,
            kdfSalt: 'AAECAwQFBgcICQoLDA0ODw',
            credentialRevision: 1,
            privateKeyWrapRevision: 1,
          ),
        ),
      );
      when(
        () => crypto.buildChangePasswordMaterial(
          currentPassword: 'old',
          newPassword: 'new',
          accountId: '00112233-4455-6677-8899-aabbccddeeff',
          currentKdfSaltBase64: 'AAECAwQFBgcICQoLDA0ODw',
          currentEncryptedPrivateKeyBase64: 'dummy',
        ),
      ).thenAnswer((_) async => material);
      when(() => keys.clear()).thenThrow(const BiometricKeyCleanupException());
      when(
        () => remote.changePassword(
          baseCredentialRevision: 1,
          basePrivateKeyWrapRevision: 1,
          currentAuthCredential: material.currentAuthCredential,
          newAuthCredential: material.newAuthCredential,
          newKdfSalt: material.kdfSalt,
          newEncryptedPrivateKey: material.encryptedPrivateKey,
        ),
      ).thenAnswer((_) async {});
      final cubit = ChangePasswordCubit(
        accountDatasource: account,
        datasource: remote,
        cryptoService: crypto,
        keyStore: keys,
      );
      await cubit.changePassword(
        email: 'dummy@example.test',
        currentPassword: 'old',
        newPassword: 'new',
      );
      expect(cubit.state, isA<ChangePasswordFailure>());
      verifyZeroInteractions(remote);
      expect(material.masterKey, everyElement(0));
      expect(material.privateKey, everyElement(0));
      await cubit.close();
    },
  );
}
