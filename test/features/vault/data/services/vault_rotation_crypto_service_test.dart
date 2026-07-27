import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test('opens the canonical pending Member Vault key package', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
    final root =
        jsonDecode(
              File(
                'test/fixtures/vault_protocol_2/vectors/rotation.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final vector = (root['pendingSealedBoxVectors'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'rotation-member-vault-key');
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => sodium,
      envelopes: VaultProtocolEnvelopeService(sodiumLoader: () async => sodium),
      signatures: VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ),
    );

    final key = await service.openMemberVaultKey(
      Map<String, dynamic>.from(vector['envelope'] as Map),
      VaultProtocolBytes.hex(vector['recipientPrivateKeyHex']! as String),
    );

    expect(
      VaultProtocolBytes.base64UrlEncode(key),
      '-VYJZRno9ZF1QKs-Yad5VLjW0Z_Xuz7EvZZjUdG8P9s',
    );
    key.fillRange(0, key.length, 0);
  });

  test('rewraps a canonical Entry DEK into the target generation', () async {
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
    final envelopeService = VaultProtocolEnvelopeService(
      sodiumLoader: () async => sodium,
    );
    final service = VaultRotationCryptoService(
      sodiumLoader: () async => sodium,
      envelopes: envelopeService,
      signatures: VaultProtocolSignatureService(
        sodiumLoader: () async => sodium,
      ),
    );
    final root =
        jsonDecode(
              File(
                'test/fixtures/vault_protocol_2/vectors/envelopes.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final vector = (root['aeadVectors'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'vault-entry-key');
    final source = Map<String, dynamic>.from(vector['envelope'] as Map);
    final targetKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

    final rewrapped = await service.rewrapEntryKey(
      source,
      VaultProtocolBytes.hex(vector['decryptionKeyHex']! as String),
      targetKey,
      5,
      4,
    );
    final opened = await envelopeService.decrypt(
      profile: VaultAadProfile.entryKeyWrapper,
      envelope: rewrapped,
      key: targetKey,
      expected: VaultEnvelopeExpectations(
        aadContext: rewrapped,
        minimumMemberKeyGeneration: 5,
      ),
    );

    expect(VaultProtocolBytes.hexEncode(opened), vector['plaintextHex']);
    opened.fillRange(0, opened.length, 0);
    targetKey.fillRange(0, targetKey.length, 0);
  });
}
