import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_import_projection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Envelopes extends Mock implements VaultEnvelopeCryptography {}

void main() {
  const vaultId = '22222233-4455-4677-8899-aabbccddeeff';
  final vaults = _Vaults();
  final keys = _Keys();
  final envelopes = _Envelopes();
  late Uint8List dek;
  late Map<VaultAadProfile, String> plaintexts;

  setUpAll(() {
    registerFallbackValue(VaultAadProfile.memberIndex);
    registerFallbackValue(Uint8List(0));
  });
  setUp(() {
    dek = Uint8List(32)..fillRange(0, 32, 7);
    plaintexts = {};
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'organizationId': '00112233-4455-4677-8899-aabbccddeeff',
        'memberKeyGeneration': 3,
        'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 5},
        'memberVaultKey': <String, dynamic>{},
        'discoveryKey': <String, dynamic>{},
      },
    );
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => keys.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => envelopes.encrypt(
        profile: any(named: 'profile'),
        context: any(named: 'context'),
        plaintext: any(named: 'plaintext'),
        key: any(named: 'key'),
      ),
    ).thenAnswer((call) async {
      plaintexts[call.namedArguments[#profile] as VaultAadProfile] = utf8
          .decode(call.namedArguments[#plaintext] as Uint8List);
      return {'nonce': 'nonce', 'ciphertext': 'ciphertext'};
    });
  });

  test(
    'creates complete ciphertext-only projections with safe policy',
    () async {
      final result =
          await CanonicalImportProjectionService(
            vaults: vaults,
            keys: keys,
            envelopes: envelopes,
            randomEntryKey: () async => dek,
          ).prepareCredentialBatch(
            vaultId: vaultId,
            entryIds: const ['33333344-5566-4788-99aa-bbccddeeff00'],
            drafts: const [
              ImportEntryDraft(
                label: 'Production',
                description: 'private folder',
                type: EntryType.credential,
                payload: {'username': 'alice', 'password': 'super-secret'},
              ),
            ],
            memberPrivateKey: Uint8List(32),
          );

      final wire = jsonEncode(result);
      expect(wire, isNot(contains('super-secret')));
      expect(wire, isNot(contains('Production')));
      expect(
        result.single.keys,
        containsAll([
          'entryId',
          'entryType',
          'entryKey',
          'memberIndex',
          'memberSecret',
          'agentDiscovery',
        ]),
      );
      expect(result.single['entryType'], 1);
      expect(
        plaintexts[VaultAadProfile.memberSecret],
        contains('agentVisibilityPolicy'),
      );
      expect(
        plaintexts[VaultAadProfile.agentDiscovery],
        isNot(contains('alice')),
      );
      expect(
        plaintexts[VaultAadProfile.agentDiscovery],
        isNot(contains('super-secret')),
      );
      expect(dek, everyElement(0));
    },
  );
}
