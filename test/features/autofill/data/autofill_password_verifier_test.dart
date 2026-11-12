import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_password_verifier.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/features/unlock/data/services/unlock_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _Account extends Mock implements AccountRemoteDatasource {}

class _Crypto extends Mock implements UnlockCryptoService {}

void main() {
  final kdf = IdentityKdfMetadata.fromJson({
    'securityVersion': 1,
    'minimumSecurityVersion': 1,
    'profileId': 'identity-argon2id-password-v1',
    'kdfSalt': 'AAECAwQFBgcICQoLDA0ODw',
    'credentialRevision': 1,
    'privateKeyWrapRevision': 1,
  });
  const claims = MemberSyncSessionAuthority(
    principalId: 'p',
    organizationId: 'o',
    organizationMembershipGeneration: '1',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );
  for (final rejectProof in [false, true]) {
    test(
      'fresh request password wipes derived keys when receipt rejection is $rejectProof',
      () async {
        final account = _Account();
        final crypto = _Crypto();
        final keys = UnlockResult(
          masterKey: Uint8List.fromList(List.filled(32, 7)),
          privateKey: Uint8List.fromList(List.filled(32, 8)),
        );
        var verified = false;
        when(account.getUnlockAccount).thenAnswer(
          (_) async => AccountResponse(
            userId: 'p',
            encryptedPrivateKey: 'synthetic',
            kdf: kdf,
          ),
        );
        when(
          () => crypto.deriveAndDecrypt(
            masterPassword: 'synthetic',
            accountId: 'p',
            kdf: kdf,
            encryptedPrivateKeyBase64: 'synthetic',
          ),
        ).thenAnswer((_) async => keys);
        final service = AutoFillPasswordVerifier(
          account: account,
          crypto: crypto,
          authority: MemberSyncSessionAuthorityProvider.independent(
            readClaims: () async => claims,
            sessionRevision: () => 0,
          ),
          captureAuthorization: () => () async {
            verified = true;
            if (rejectProof) throw StateError('canceled request');
          },
        );
        if (rejectProof) {
          await expectLater(service.verify('synthetic'), throwsStateError);
        } else {
          await service.verify('synthetic');
        }
        expect(verified, isTrue);
        expect(keys.masterKey, everyElement(0));
        expect(keys.privateKey, everyElement(0));
      },
    );
  }
  test(
    'authority change during KDF cannot authorize and wipes the derived keys',
    () async {
      final account = _Account();
      final crypto = _Crypto();
      var revision = 0;
      var authorized = false;
      final keys = UnlockResult(
        masterKey: Uint8List.fromList(List.filled(32, 7)),
        privateKey: Uint8List.fromList(List.filled(32, 8)),
      );
      when(account.getUnlockAccount).thenAnswer(
        (_) async => AccountResponse(
          userId: 'p',
          encryptedPrivateKey: 'synthetic',
          kdf: kdf,
        ),
      );
      when(
        () => crypto.deriveAndDecrypt(
          masterPassword: 'synthetic',
          accountId: 'p',
          kdf: kdf,
          encryptedPrivateKeyBase64: 'synthetic',
        ),
      ).thenAnswer((_) async {
        revision++;
        return keys;
      });
      final verifier = AutoFillPasswordVerifier(
        account: account,
        crypto: crypto,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => claims,
          sessionRevision: () => revision,
        ),
        captureAuthorization: () => () async {
          authorized = true;
        },
      );
      await expectLater(
        verifier.verify('synthetic'),
        throwsStateError,
      );
      expect(authorized, isFalse);
      expect(keys.masterKey, everyElement(0));
      expect(keys.privateKey, everyElement(0));
    },
  );
}
