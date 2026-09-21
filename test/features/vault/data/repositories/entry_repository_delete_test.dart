import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Crypto extends Mock implements EntryCryptoService {}

class _Canonical extends Mock implements CanonicalEntryDetailService {}

class _Index extends Mock implements MemberIndexReader {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(() => true);
    registerFallbackValue(
      EntryEntity(
        id: 'entry',
        vaultId: 'vault',
        label: '',
        type: EntryType.key,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  });

  for (final fails in [false, true]) {
    test(
      'repository delegates deletion and wipes the borrowed key (failure: $fails)',
      () async {
        final entries = _Entries();
        final canonical = _Canonical();
        final index = _Index();
        final sessions = VaultSessionStore()
          ..setMemberPrivateKey(Uint8List(32)..fillRange(0, 32, 7));
        addTearDown(sessions.clear);
        when(() => index.entries('vault')).thenReturn([
          const MemberIndexEntry(
            entryId: 'entry',
            entryType: 0,
            memberLabel: 'Key',
            searchFields: [],
            revision: '7',
            currentKeyVersion: 2,
            state: MemberEntryState.active,
          ),
        ]);
        late Uint8List borrowed;
        late bool Function() current;
        when(
          () => canonical.deleteEntry(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
            isSessionCurrent: any(named: 'isSessionCurrent'),
          ),
        ).thenAnswer((call) async {
          final expected = call.namedArguments[#expected] as EntryEntity;
          expect(expected.currentRevision, '7');
          expect(expected.currentKeyVersion, 2);
          borrowed = call.namedArguments[#memberPrivateKey] as Uint8List;
          current = call.namedArguments[#isSessionCurrent] as bool Function();
          expect(borrowed, everyElement(7));
          expect(current(), isTrue);
          if (fails) {
            throw const CanonicalEntryDetailException(
              CanonicalEntryDetailError.conflict,
            );
          }
        });
        final repository = EntryRepositoryImpl(
          entryDatasource: entries,
          vaultDatasource: _Vaults(),
          cryptoService: _Crypto(),
          canonicalDetails: canonical,
          sessions: sessions,
          memberIndex: index,
        );
        final operation = repository.deleteEntry(
          vaultId: 'vault',
          entryId: 'entry',
        );
        if (fails) {
          await expectLater(
            operation,
            throwsA(
              isA<EntryException>().having(
                (e) => e.kind,
                'kind',
                EntryErrorKind.validation,
              ),
            ),
          );
        } else {
          await operation;
        }
        expect(borrowed, everyElement(0));
        sessions.clear();
        expect(current(), isFalse);
        verifyNever(() => entries.deleteEntry(any(), any(), any()));
      },
    );
  }
}
