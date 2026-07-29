import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/encrypted_vault_summary_model.dart';

void main() {
  Map<String, Object?> vaultJson() => {
    'id': '22222222-2222-4222-8222-222222222222',
    'isDefault': false,
    'protocolVersion': 2,
    'memberSequence': '1',
    'discoverySequence': '2',
    'memberKeyGeneration': 1,
    'memberVaultMetadata': {'descriptor': {}},
    'memberVaultKey': {'wrappedVaultKey': {}},
    'currentKeyEpoch': {'vaultKeyVersion': 1},
    'discoveryKey': {'descriptor': {}},
    'vaultPrivateKeys': [
      {'descriptor': {}},
      {'descriptor': {}},
    ],
    'createdAt': '2026-07-29T10:00:00Z',
    'updatedAt': '2026-07-29T10:00:00Z',
    'memberCount': 1,
    'entryCount': 0,
    'activeGrantCount': 0,
  };

  test('encrypted Vault summary requires canonical structural fields', () {
    final model = EncryptedVaultSummaryModel.fromJson(vaultJson());
    expect(model.memberSequence, '1');
    expect(model.discoverySequence, '2');
    expect(model.vaultPrivateKeys, hasLength(2));

    final missingDiscoveryKey = vaultJson()..remove('discoveryKey');
    expect(
      () => EncryptedVaultSummaryModel.fromJson(missingDiscoveryKey),
      throwsFormatException,
    );
  });

  test('encrypted asset metadata parses camelCase backend enum names', () {
    Map<String, Object?> metadata(String target) => {
      'assetId': '33333333-3333-4333-8333-333333333333',
      'target': target,
      'entryId': target == 'entry'
          ? '44444444-4444-4444-8444-444444444444'
          : null,
      'mediaType': 'image/png',
      'ciphertextLength': 42,
      'ciphertextSha256': 'digest',
      'downloadUrl': 'https://assets.example/ciphertext',
    };

    expect(
      EncryptedPresentationAssetMetadata.fromJson(metadata('vault')).target,
      1,
    );
    expect(
      EncryptedPresentationAssetMetadata.fromJson(metadata('entry')).target,
      2,
    );
    expect(
      () => EncryptedPresentationAssetMetadata.fromJson(metadata('Vault')),
      throwsFormatException,
    );
  });
}
