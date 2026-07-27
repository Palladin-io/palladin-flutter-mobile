import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_list_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

void main() {
  test('decrypts canonical metadata and isolates a corrupt Vault', () async {
    final root =
        jsonDecode(
              File(
                'test/fixtures/vault_protocol_2/vectors/envelopes.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final metadata = (root['aeadVectors'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'member-vault-metadata');
    final memberKey = (root['sealedBoxVectors'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['id'] == 'member-vault-key');
    final good = <String, dynamic>{
      'id': '22222222-2222-4222-8222-222222222222',
      'protocolVersion': 2,
      'memberKeyGeneration': 4,
      'memberVaultMetadata': metadata['envelope'],
      'memberVaultKey': memberKey['envelope'],
      'createdAt': '2026-07-16T10:00:00Z',
      'updatedAt': '2026-07-16T11:00:00Z',
      'memberCount': 2,
      'entryCount': 7,
      'activeGrantCount': 1,
    };
    final corrupt = Map<String, dynamic>.from(good)
      ..['id'] = '33333333-3333-4333-8333-333333333333';
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'vaults': [good, corrupt],
                'total': 2,
              },
            ),
          ),
        ),
      );
    final library = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    final sodium = await _loadSodium(library);
    if (sodium == null) {
      markTestSkipped('libsodium is unavailable on this test host');
      return;
    }
    Future<sodium_ffi.SodiumSumo> loader() async => sodium;
    final envelopes = VaultProtocolEnvelopeService(sodiumLoader: loader);
    final service = VaultListCryptoService(
      remote: VaultRemoteDatasource(dio),
      keys: VaultRotationCryptoService(
        sodiumLoader: loader,
        envelopes: envelopes,
      ),
      envelopes: envelopes,
    );

    final result = await service.load(
      VaultProtocolBytes.hex(memberKey['recipientPrivateKeyHex'] as String),
    );

    expect(result.vaults.single.name, 'Engineering Vault');
    expect(result.vaults.single.description, 'Synthetic CVT-398 fixture');
    expect(result.vaults.single.entryCount, 7);
    expect(result.corruptIds, ['33333333-3333-4333-8333-333333333333']);
  });
}

Future<sodium_ffi.SodiumSumo?> _loadSodium(String? library) async {
  try {
    return await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(library ?? 'libsodium.so'),
    );
  } on ArgumentError {
    return null;
  }
}
