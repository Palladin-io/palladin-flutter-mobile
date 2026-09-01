import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/identity/organization_member_directory_service.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_history_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Canonical extends Mock implements CanonicalEntryDetailService {}

class _TokenStorage extends Mock implements SecureTokenStorage {}

class _DirectoryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'items': [
        {'userId': 'member-id', 'displayName': 'Patryk Roguszewski'},
      ],
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Entries entries;
  late _Canonical canonical;
  late OrganizationMemberDirectoryService memberDirectory;
  late EntryHistoryService service;

  final entry = EntryEntity(
    id: 'entry-id',
    vaultId: 'vault-id',
    label: 'Entry',
    type: EntryType.key,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    currentRevision: '7',
  );

  setUpAll(() {
    registerFallbackValue(entry);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      CanonicalEntrySnapshot(entry: {}, payload: {}, secret: {}),
    );
    registerFallbackValue(EntryType.key);
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    entries = _Entries();
    canonical = _Canonical();
    final tokenStorage = _TokenStorage();
    when(
      () => tokenStorage.accessToken,
    ).thenAnswer((_) async => _token('organization-id'));
    memberDirectory = OrganizationMemberDirectoryService(
      dio: Dio()..httpClientAdapter = _DirectoryAdapter(),
      tokenStorage: tokenStorage,
    );
    service = EntryHistoryService(
      entries: entries,
      canonical: canonical,
      memberDirectory: memberDirectory,
    );
  });

  test(
    'resolves Member actors without placing names in history ciphertext',
    () async {
      when(
        () => entries.getEntryHistory(
          entry.vaultId,
          entry.id,
          beforeRevision: any(named: 'beforeRevision'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => {
          'items': [
            {
              'revision': '7',
              'changedAt': '2026-09-01T12:30:00Z',
              'changedByType': 1,
              'changedById': 'member-id',
              'operation': 2,
              'memberSecret': <String, dynamic>{},
            },
          ],
          'nextBeforeRevision': null,
        },
      );
      final page = await service.loadPage(entry);

      expect(page.items.single.actorName, 'Patryk Roguszewski');
      expect(page.items.single.encrypted, isNot(contains('actorName')));
    },
  );

  test('restore forwards the historical color into the new revision', () async {
    final current = CanonicalEntrySnapshot(
      entry: {'currentRevision': '7'},
      payload: {'value': 'current'},
      secret: {},
    );
    final selected = CanonicalEntryHistorySnapshot(
      secret: {'entryType': 0, 'memberLabel': 'Old label', 'color': '#60A5FA'},
      payload: {'value': 'old'},
    );
    when(
      () => canonical.reveal(
        expected: entry,
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => current);
    when(
      () => canonical.update(
        snapshot: any(named: 'snapshot'),
        expected: entry,
        label: any(named: 'label'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        color: any(named: 'color'),
        type: any(named: 'type'),
        content: any(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => entry);

    await service.restore(
      entry: entry,
      selected: selected,
      privateKey: Uint8List(32),
    );

    verify(
      () => canonical.update(
        snapshot: current,
        expected: entry,
        label: 'Old label',
        description: '',
        icon: '',
        color: '#60A5FA',
        type: EntryType.key,
        content: {'value': 'old'},
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
  });
}

String _token(String organizationId) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none'})}.${encode({'org_id': organizationId})}.sig';
}
