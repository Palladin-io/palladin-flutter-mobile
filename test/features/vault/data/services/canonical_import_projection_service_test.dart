import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_import_projection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _VaultCrypto extends Mock implements VaultCryptoService {}

Future<SodiumSumo?> _loadSodium() async {
  try {
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    if (configured != null) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open(configured),
      );
    }
    if (Platform.isLinux) {
      return await sodium_ffi.SodiumSumoInit.init(
        () => DynamicLibrary.open('libsodium.so'),
      );
    }
    return await SodiumSumoInit.init();
  } catch (_) {
    return null;
  }
}

void main() {
  const vaultId = '22222233-4455-4677-8899-aabbccddeeff';
  const organizationId = '00112233-4455-4677-8899-aabbccddeeff';
  final vaults = _Vaults();
  final vaultCrypto = _VaultCrypto();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'id': vaultId,
        'organizationId': organizationId,
        'memberKeyGeneration': 3,
        'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 5},
        'memberVaultKey': <String, dynamic>{},
        'discoveryKey': <String, dynamic>{},
      },
    );
  });

  test(
    'uses the canonical create pipeline and emits ciphertext-only contracts',
    () async {
      final sodium = await _loadSodium();
      if (sodium == null) {
        markTestSkipped('libsodium is unavailable in this Flutter test host');
        return;
      }
      final retainedVaultKey = Uint8List(32)..fillRange(0, 32, 1);
      final openedVaultKey = Uint8List.fromList(retainedVaultKey);
      final openedDiscoveryKey = Uint8List(32)..fillRange(0, 32, 2);
      when(
        () => vaultCrypto.openVaultProjection(
          json: any(named: 'json'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => _openedVault(
          vaultKey: openedVaultKey,
          discoveryKey: openedDiscoveryKey,
        ),
      );
      final entryCrypto = EntryV2CryptoService(
        sodiumLoader: () async => sodium,
      );

      final result =
          await CanonicalImportProjectionService(
            vaults: vaults,
            vaultCrypto: vaultCrypto,
            entryCrypto: entryCrypto,
          ).prepareCredentialBatch(
            vaultId: vaultId,
            entryIds: const ['33333344-5566-4788-99aa-bbccddeeff00'],
            drafts: const [
              ImportEntryDraft(
                label: 'Production',
                description: 'private folder',
                type: EntryType.credential,
                payload: {
                  'username': 'alice',
                  'password': 'synthetic-secret',
                  'url': 'https://example.invalid/login',
                  'totp':
                      'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example',
                },
              ),
            ],
            memberPrivateKey: Uint8List(32),
          );

      final wire = result.single.toString();
      expect(wire, isNot(contains('synthetic-secret')));
      expect(wire, isNot(contains('Production')));
      expect(result.single, isNot(contains('vaultId')));
      expect(
        result.single.keys,
        containsAll([
          'entryId',
          'entryKey',
          'memberIndex',
          'memberSecret',
          'agentDiscovery',
          'deliveryPolicy',
        ]),
      );
      final entryKey = Map<String, dynamic>.from(
        result.single['entryKey']! as Map,
      );
      expect(entryKey.keys, containsAll(['descriptor', 'encodedSuitePayload']));
      expect(entryKey, isNot(contains('header')));

      final secret = await entryCrypto.openMemberSecret(
        entryKey: entryKey,
        memberSecret: Map<String, dynamic>.from(
          result.single['memberSecret']! as Map,
        ),
        vaultKey: retainedVaultKey,
      );
      final content = Map<String, dynamic>.from(secret['content']! as Map);
      final policy = Map<String, dynamic>.from(
        secret['agentFieldAccess']! as Map,
      );
      expect(secret['memberLabel'], 'Production');
      expect(content['password'], 'synthetic-secret');
      expect(content['urlDomain'], 'example.invalid');
      expect(content['totp'], isA<Map>());
      expect(policy['credential.username'], 'discovery');
      expect(policy['credential.urlDomain'], 'discovery');
      expect(policy['credential.totp'], 'onGrantDerived');
      expect(openedVaultKey, everyElement(0));
      expect(openedDiscoveryKey, everyElement(0));
      retainedVaultKey.fillRange(0, retainedVaultKey.length, 0);
    },
  );

  test('rejects a decrypted Vault wrapper bound to another Vault', () async {
    final vaultKey = Uint8List(32)..fillRange(0, 32, 1);
    final discoveryKey = Uint8List(32)..fillRange(0, 32, 2);
    when(
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => _openedVault(
        vaultId: '33333344-5566-4788-99aa-bbccddeeff00',
        vaultKey: vaultKey,
        discoveryKey: discoveryKey,
      ),
    );

    await expectLater(
      CanonicalImportProjectionService(
        vaults: vaults,
        vaultCrypto: vaultCrypto,
        entryCrypto: EntryV2CryptoService(),
      ).prepareCredentialBatch(
        vaultId: vaultId,
        entryIds: const ['33333344-5566-4788-99aa-bbccddeeff00'],
        drafts: const [
          ImportEntryDraft(
            label: 'Entry',
            type: EntryType.credential,
            payload: {'username': 'user', 'password': 'password'},
          ),
        ],
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<CanonicalImportPreparationException>().having(
          (error) => error.stage,
          'stage',
          CanonicalImportPreparationStage.wrapperVaultBinding,
        ),
      ),
    );
    expect(vaultKey, everyElement(0));
    expect(discoveryKey, everyElement(0));
  });
}

OpenedVaultProjection _openedVault({
  String vaultId = '22222233-4455-4677-8899-aabbccddeeff',
  Uint8List? vaultKey,
  Uint8List? discoveryKey,
}) => OpenedVaultProjection(
  organizationId: '00112233-4455-4677-8899-aabbccddeeff',
  vaultId: vaultId,
  vaultKey: vaultKey ?? Uint8List(32),
  vaultDiscoveryKey: discoveryKey ?? Uint8List(32),
  metadata: const MemberVaultMetadata(
    name: 'Personal',
    description: null,
    icon: null,
    color: null,
    grantMode: 'full',
  ),
  epoch: const VaultKeyEpochModel(
    vaultKeyVersion: 4,
    vdkVersion: 5,
    agentMessageKeyVersion: 6,
    manifestSigningKeyVersion: 7,
  ),
  memberKeyGeneration: 3,
  wrapper: const MemberVaultKeyWrapperMetadata(
    wrapperSuiteId: 'palladin-x25519-sealed-box-v1',
    wrappedKeyVersion: 4,
    memberKeyGeneration: 3,
    recipientKeyVersion: 1,
    recipientFingerprint: 'fingerprint',
  ),
);
