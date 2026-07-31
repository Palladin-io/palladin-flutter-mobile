import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/import_entries_request.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_import_projection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Crypto extends Mock implements EntryCryptoService {}

class _Canonical extends Mock implements CanonicalImportProjectionService {}

class _Request extends Fake implements ImportEntriesRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<String>[]);
    registerFallbackValue(<ImportEntryDraft>[]);
    registerFallbackValue(_Request());
  });

  test(
    'retry resumes after committed batch and reuses failed ciphertext',
    () async {
      final entries = _Entries();
      final canonical = _Canonical();
      final requests = <ImportEntriesRequest>[];
      var send = 0;
      var issued = 0;
      when(
        () => entries.issueCreationChallenges('vault', count: 1),
      ).thenAnswer((_) async => ['id-${issued++}']);
      var prepared = 0;
      when(
        () => canonical.prepareCredentialBatch(
          vaultId: 'vault',
          entryIds: any(named: 'entryIds'),
          drafts: any(named: 'drafts'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => [
          {
            'entryId': 'prepared-${prepared++}',
            'ciphertext': 'opaque-$prepared',
          },
        ],
      );
      when(() => entries.importEntries('vault', any())).thenAnswer((
        call,
      ) async {
        requests.add(call.positionalArguments[1] as ImportEntriesRequest);
        send++;
        if (send == 2 || send == 3) {
          throw DioException(
            requestOptions: RequestOptions(path: '/import'),
            type: DioExceptionType.connectionError,
          );
        }
        return 1;
      });
      final repository = EntryRepositoryImpl(
        entryDatasource: entries,
        vaultDatasource: _Vaults(),
        cryptoService: _Crypto(),
        canonicalImport: canonical,
      );
      const drafts = [
        ImportEntryDraft(label: 'A', type: EntryType.credential, payload: {}),
        ImportEntryDraft(label: 'B', type: EntryType.credential, payload: {}),
      ];
      await expectLater(
        repository.importEntriesEncrypted(
          vaultId: 'vault',
          format: 'csv',
          creates: drafts,
          overwrites: const [],
          privateKey: Uint8List(32),
          chunkSize: 1,
        ),
        throwsA(isA<Object>()),
      );
      final result = await repository.importEntriesEncrypted(
        vaultId: 'vault',
        format: 'csv',
        creates: drafts,
        overwrites: const [],
        privateKey: Uint8List(32),
        chunkSize: 1,
      );

      expect(result.createdCount, 2);
      expect(prepared, 2, reason: 'failed batch ciphertext must be reused');
      expect(identical(requests[1], requests[2]), isTrue);
      final firstRetryBody = utf8.encode(jsonEncode(requests[2].toJson()));
      final resumedRetryBody = utf8.encode(jsonEncode(requests[3].toJson()));
      expect(resumedRetryBody, orderedEquals(firstRetryBody));
    },
  );
}
