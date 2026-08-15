import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_model.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';

class _MockEntryRemoteDatasource extends Mock
    implements EntryRemoteDatasource {}

class _MockVaultRemoteDatasource extends Mock
    implements VaultRemoteDatasource {}

class _MockEntryCryptoService extends Mock implements EntryCryptoService {}

void main() {
  for (final retired in const {'securityCode': '123', 'pin': '4321'}.entries) {
    test(
      'revealEntry rejects retired ${retired.key} field',
      () => _expectRetiredFieldRejected(retired.key, retired.value),
    );
  }
}

Future<void> _expectRetiredFieldRejected(
  String retiredField,
  String retiredValue,
) async {
  final entryDatasource = _MockEntryRemoteDatasource();
  final cryptoService = _MockEntryCryptoService();
  final privateKey = Uint8List(32);
  final vaultKey = Uint8List.fromList(List<int>.filled(32, 7));
  const content = EntryContentModel(
    encryptedBlob: 'ciphertext',
    nonce: 'nonce',
  );
  const detail = EntryDetailModel(
    summary: EntryModel(
      id: 'entry-1',
      vaultId: 'vault-1',
      label: 'Corporate card',
      type: 3,
      createdAt: '2026-08-01T00:00:00Z',
      updatedAt: '2026-08-01T00:00:00Z',
    ),
    content: content,
  );
  when(
    () => entryDatasource.getEntry('vault-1', 'entry-1'),
  ).thenAnswer((_) async => detail);
  when(
    () =>
        cryptoService.unwrapVK(wrappedVK: 'wrapped-vk', privateKey: privateKey),
  ).thenAnswer((_) async => vaultKey);
  when(
    () => cryptoService.decryptEntry(content: content, vaultKey: vaultKey),
  ).thenAnswer(
    (_) async => {
      'v': 2,
      'type': 'CREDIT_CARD',
      'cardholderName': 'Ada Lovelace',
      'cardNumber': '4242424242424242',
      'expiryMonth': '12',
      'expiryYear': '2030',
      retiredField: retiredValue,
    },
  );
  final repository = EntryRepositoryImpl(
    entryDatasource: entryDatasource,
    vaultDatasource: _MockVaultRemoteDatasource(),
    cryptoService: cryptoService,
  );

  await expectLater(
    repository.revealEntry(
      vaultId: 'vault-1',
      entryId: 'entry-1',
      privateKey: privateKey,
      wrappedVK: 'wrapped-vk',
    ),
    throwsFormatException,
  );
  expect(vaultKey, everyElement(0));
}
