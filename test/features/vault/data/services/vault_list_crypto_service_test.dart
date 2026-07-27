import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/encrypted_vault_summary_model.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_list_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

class _Remote extends Mock implements VaultRemoteDatasource {}

class _Crypto extends Mock implements VaultCryptoService {}

void main() {
  late _Remote remote;
  late _Crypto crypto;
  late EncryptedVaultSummaryModel summary;
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() {
    remote = _Remote();
    crypto = _Crypto();
    summary = EncryptedVaultSummaryModel.fromJson({
      'id': '22222222-2222-4222-8222-222222222222',
      'protocolVersion': 2,
      'memberKeyGeneration': 4,
      'memberVaultMetadata': {'descriptor': {}},
      'memberVaultKey': {'wrappedVaultKey': {}},
      'currentKeyEpoch': {
        'vaultKeyVersion': 7,
        'vdkVersion': 8,
        'agentMessageKeyVersion': 9,
        'manifestSigningKeyVersion': 10,
      },
      'createdAt': '2026-07-16T10:00:00Z',
      'updatedAt': '2026-07-16T11:00:00Z',
      'memberCount': 2,
      'entryCount': 7,
      'activeGrantCount': 1,
    });
    when(
      () => remote.listEncryptedVaults(offset: 0),
    ).thenAnswer((_) async => EncryptedVaultPage(vaults: [summary], total: 1));
    when(
      () => crypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => OpenedVaultProjection(
        organizationId: '00112233-4455-4677-8899-aabbccddeeff',
        vaultId: summary.id,
        vaultKey: Uint8List(32),
        vaultDiscoveryKey: null,
        metadata: const MemberVaultMetadata(
          name: 'Engineering',
          description: 'Canonical',
          icon: GlyphVaultIcon('shield'),
          color: '#EB4747',
          grantMode: 'full',
        ),
        epoch: const VaultKeyEpochModel(
          vaultKeyVersion: 7,
          vdkVersion: 8,
          agentMessageKeyVersion: 9,
          manifestSigningKeyVersion: 10,
        ),
        memberKeyGeneration: 4,
        wrapper: const MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: 'suite',
          wrappedKeyVersion: 7,
          memberKeyGeneration: 4,
          recipientKeyVersion: 1,
          recipientFingerprint: 'fp',
        ),
      ),
    );
  });

  test(
    'reads list metadata only through canonical Vault projection opener',
    () async {
      final result = await VaultListCryptoService(
        remote: remote,
        crypto: crypto,
      ).load(Uint8List(32));
      expect(result.vaults.single.name, 'Engineering');
      expect(result.vaults.single.icon, 'shield');
      expect(result.vaults.single.grantMode.name, 'full');
      final json =
          verify(
                () => crypto.openVaultProjection(
                  json: captureAny(named: 'json'),
                  memberPrivateKey: any(named: 'memberPrivateKey'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(json['memberVaultMetadata'], summary.memberVaultMetadata);
      expect(json['currentKeyEpoch'], summary.currentKeyEpoch);
    },
  );
}
