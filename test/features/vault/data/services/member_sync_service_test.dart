import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';

const _oldId = '33333333-3333-4333-8333-333333333330';
const _firstId = '33333333-3333-4333-8333-333333333331';
const _secondId = '33333333-3333-4333-8333-333333333332';
const _newId = '33333333-3333-4333-8333-333333333339';

class _Remote extends Mock implements MemberSyncRemote {}

class _EntryCrypto extends Mock implements EntryV2CryptoService {}

class _MemoryCache implements MemberSyncCache {
  String? appliedSequence;
  final Map<String, MemberSyncItemModel> heads = {};
  var snapshotReplacements = 0;
  var deltaApplications = 0;

  @override
  Future<void> applyDelta(
    String vaultId,
    String sequence,
    List<MemberSyncItemModel> items,
  ) async {
    deltaApplications += 1;
    for (final item in items) {
      if (item.isTombstone) {
        heads.remove(item.entryId);
      } else {
        heads[item.entryId] = item;
      }
    }
    appliedSequence = sequence;
  }

  @override
  Future<void> clearVault(String vaultId) async {
    heads.clear();
    appliedSequence = null;
  }

  @override
  Stream<MemberSyncItemModel> readHeads(String vaultId) =>
      Stream.fromIterable(heads.values);

  @override
  Future<void> replaceSnapshot(
    String vaultId,
    String sequence,
    Stream<MemberSyncItemModel> items,
  ) async {
    final staged = {
      for (final item in await items.toList()) item.entryId: item,
    };
    heads
      ..clear()
      ..addAll(staged);
    appliedSequence = sequence;
    snapshotReplacements += 1;
  }

  @override
  Future<String?> sequence(String vaultId) async => appliedSequence;
}

class _BlockingReadCache extends _MemoryCache {
  final controller = StreamController<MemberSyncItemModel>();

  @override
  Stream<MemberSyncItemModel> readHeads(String vaultId) => controller.stream;
}

void main() {
  late _Remote remote;
  late _EntryCrypto entryCrypto;
  late _MemoryCache cache;
  late MemberSyncService service;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    remote = _Remote();
    entryCrypto = _EntryCrypto();
    cache = _MemoryCache();
    service = MemberSyncService(
      remote: remote,
      cache: cache,
      entryCrypto: entryCrypto,
    );
    when(
      () => entryCrypto.openEntryDek(
        entryKey: any(named: 'entryKey'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => entryCrypto.openMemberIndex(
        envelope: any(named: 'envelope'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((invocation) async {
      final envelope = invocation.namedArguments[#envelope]! as Map;
      final scope = (envelope['descriptor'] as Map)['scope'] as Map;
      return _memberIndex('Database ${scope['entryId']}');
    });
    when(
      () => remote.delta(
        vaultId: any(named: 'vaultId'),
        afterSequence: any(named: 'afterSequence'),
        continuationCursor: any(named: 'continuationCursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((invocation) async {
      final afterSequence =
          invocation.namedArguments[#afterSequence] as String? ?? '0';
      return MemberDeltaSuccess(
        MemberDeltaPage(
          deltaUpperBound: afterSequence,
          appliedThroughSequence: afterSequence,
          items: const [],
        ),
      );
    });
  });

  test(
    'complete paginated snapshot becomes searchable then lock wipes it',
    () async {
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((invocation) async {
        final cursor = invocation.namedArguments[#cursor] as String?;
        return cursor == null
            ? MemberSnapshotPage(
                snapshotBaseSequence: '7',
                items: [_head(_firstId)],
                nextCursor: 'next',
              )
            : MemberSnapshotPage(
                snapshotBaseSequence: '7',
                items: [_head(_secondId)],
              );
      });

      final indexUpdate = expectLater(service.indexUpdates, emits('vault'));
      final result = await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );
      await indexUpdate;

      expect(result.sequence, '7');
      expect(result.entryCount, 2);
      expect(result.usedSnapshot, isTrue);
      expect(service.search('postgres', vaultId: 'vault').length, 2);
      final entries = service.entries('vault');
      expect(entries, hasLength(2));
      expect(entries.every((entry) => !entry.corrupt), isTrue);
      expect(entries.first.memberLabel, startsWith('Database '));
      expect(
        entries.first.iconReference,
        'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fexample.png',
      );
      service.lock();
      expect(service.search('postgres', vaultId: 'vault'), isEmpty);
    },
  );

  test(
    'lock invalidates an in-flight snapshot before plaintext install',
    () async {
      final pending = Completer<MemberSnapshotPage>();
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) => pending.future);

      final sync = service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );
      service.lock();
      pending.complete(
        MemberSnapshotPage(snapshotBaseSequence: '1', items: [_head(_firstId)]),
      );

      await expectLater(sync, throwsA(isA<Exception>()));
      expect(service.entries('vault'), isEmpty);
      expect(service.search('database', vaultId: 'vault'), isEmpty);
    },
  );

  test('concurrent synchronization shares one snapshot chain', () async {
    final pending = Completer<MemberSnapshotPage>();
    when(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) => pending.future);

    final first = service.synchronize(
      vaultId: 'vault',
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: 1,
    );
    final second = service.synchronize(
      vaultId: 'vault',
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: 1,
    );

    expect(identical(first, second), isTrue);
    pending.complete(
      MemberSnapshotPage(snapshotBaseSequence: '1', items: [_head(_firstId)]),
    );
    await Future.wait([first, second]);

    verify(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).called(1);
  });

  test('snapshot is closed with delta from its base sequence', () async {
    when(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => MemberSnapshotPage(
        snapshotBaseSequence: '7',
        items: [_head(_firstId)],
      ),
    );
    when(
      () => remote.delta(
        vaultId: 'vault',
        afterSequence: '7',
        continuationCursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => MemberDeltaSuccess(
        MemberDeltaPage(
          deltaUpperBound: '8',
          appliedThroughSequence: '8',
          items: [_head(_secondId)],
        ),
      ),
    );

    final result = await service.synchronize(
      vaultId: 'vault',
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: 1,
    );

    expect(result.sequence, '8');
    expect(result.usedSnapshot, isTrue);
    expect(result.entryCount, 2);
    expect(cache.appliedSequence, '8');
    verify(
      () => remote.delta(
        vaultId: 'vault',
        afterSequence: '7',
        continuationCursor: null,
        pageSize: any(named: 'pageSize'),
      ),
    ).called(1);
  });

  test('lock invalidates an in-flight cached-index rebuild', () async {
    final blockingCache = _BlockingReadCache();
    final guarded = MemberSyncService(
      remote: remote,
      cache: blockingCache,
      entryCrypto: entryCrypto,
    );
    final rebuild = guarded.unlockCached(
      vaultId: 'vault',
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: 1,
    );
    final invalidated = expectLater(rebuild, throwsA(isA<Exception>()));

    guarded.lock();
    blockingCache.controller.add(_head(_firstId));
    await blockingCache.controller.close();

    await invalidated;
    expect(guarded.entries('vault'), isEmpty);
  });

  test(
    'resetRequired discards incremental path and installs a snapshot',
    () async {
      cache
        ..appliedSequence = '4'
        ..heads[_oldId] = _head(_oldId);
      var deltaCalls = 0;
      when(
        () => remote.delta(
          vaultId: 'vault',
          afterSequence: any(named: 'afterSequence'),
          continuationCursor: any(named: 'continuationCursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) async {
        deltaCalls += 1;
        if (deltaCalls == 1) {
          return const MemberDeltaResetRequired(
            MemberSyncReset(currentSequence: '10', minRetainedSequence: '8'),
          );
        }
        return MemberDeltaSuccess(
          const MemberDeltaPage(
            deltaUpperBound: '10',
            appliedThroughSequence: '10',
            items: [],
          ),
        );
      });
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => MemberSnapshotPage(
          snapshotBaseSequence: '10',
          items: [_head(_newId)],
        ),
      );

      final result = await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );

      expect(result.usedSnapshot, isTrue);
      expect(cache.snapshotReplacements, 1);
      expect(cache.deltaApplications, 0);
      expect(cache.heads.keys, [_newId]);
    },
  );

  test('bounds repeated resetRequired responses after snapshots', () async {
    cache.appliedSequence = '4';
    when(
      () => remote.delta(
        vaultId: 'vault',
        afterSequence: any(named: 'afterSequence'),
        continuationCursor: any(named: 'continuationCursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => const MemberDeltaResetRequired(
        MemberSyncReset(currentSequence: '10', minRetainedSequence: '8'),
      ),
    );
    when(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async =>
          const MemberSnapshotPage(snapshotBaseSequence: '10', items: []),
    );
    final bounded = MemberSyncService(
      remote: remote,
      cache: cache,
      entryCrypto: entryCrypto,
      maximumSnapshotRestarts: 1,
    );

    await expectLater(
      bounded.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      ),
      throwsA(isA<StateError>()),
    );

    verify(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).called(2);
    expect(bounded.entries('vault'), isEmpty);
  });

  test(
    'delta with a newer generation fails before advancing ciphertext cache',
    () async {
      cache
        ..appliedSequence = '4'
        ..heads[_oldId] = _head(_oldId);
      when(
        () => remote.delta(
          vaultId: 'vault',
          afterSequence: any(named: 'afterSequence'),
          continuationCursor: any(named: 'continuationCursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => MemberDeltaSuccess(
          MemberDeltaPage(
            deltaUpperBound: '5',
            appliedThroughSequence: '5',
            items: [_head(_newId, generation: 2)],
          ),
        ),
      );

      await expectLater(
        service.synchronize(
          vaultId: 'vault',
          vaultKey: Uint8List(32),
          minimumMemberKeyGeneration: 1,
        ),
        throwsA(
          isA<MemberVaultKeyContextStaleException>().having(
            (error) => error.requiredGeneration,
            'requiredGeneration',
            2,
          ),
        ),
      );

      expect(cache.appliedSequence, '4');
      expect(cache.deltaApplications, 0);
      expect(service.entries('vault').single.entryId, _oldId);
    },
  );

  test(
    'snapshot with a newer generation fails before replacing ciphertext cache',
    () async {
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => MemberSnapshotPage(
          snapshotBaseSequence: '1',
          items: [_head(_newId, generation: 2)],
        ),
      );

      await expectLater(
        service.synchronize(
          vaultId: 'vault',
          vaultKey: Uint8List(32),
          minimumMemberKeyGeneration: 1,
        ),
        throwsA(isA<MemberVaultKeyContextStaleException>()),
      );

      expect(cache.snapshotReplacements, 0);
      expect(cache.appliedSequence, isNull);
      expect(service.entries('vault'), isEmpty);
    },
  );

  test(
    'corrupt projection is isolated while its ciphertext delta advances',
    () async {
      cache
        ..appliedSequence = '4'
        ..heads[_oldId] = _head(_oldId);
      when(
        () => remote.delta(
          vaultId: 'vault',
          afterSequence: any(named: 'afterSequence'),
          continuationCursor: any(named: 'continuationCursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => MemberDeltaSuccess(
          MemberDeltaPage(
            deltaUpperBound: '5',
            appliedThroughSequence: '5',
            items: [_head(_newId)],
          ),
        ),
      );
      when(
        () => entryCrypto.openMemberIndex(
          envelope: any(named: 'envelope'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenThrow(const FormatException('authentication failed'));

      await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );
      expect(cache.appliedSequence, '5');
      expect(cache.deltaApplications, 1);
      final corrupt = service
          .entries('vault')
          .singleWhere((entry) => entry.entryId == _newId);
      expect(corrupt.corrupt, isTrue);
      expect(corrupt.memberLabel, '33333333…333339');
    },
  );

  test('snapshot rejects a response above the protocol page ceiling', () async {
    when(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => MemberSnapshotPage(
        snapshotBaseSequence: '1',
        items: List.generate(201, (index) => _head(_entryId(index))),
      ),
    );

    await expectLater(
      service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(cache.snapshotReplacements, 0);
  });

  test('snapshot decrypt work never exceeds configured concurrency', () async {
    var activeDecrypts = 0;
    var maximumActiveDecrypts = 0;
    when(
      () => entryCrypto.openEntryDek(
        entryKey: any(named: 'entryKey'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async {
      activeDecrypts += 1;
      if (activeDecrypts > maximumActiveDecrypts) {
        maximumActiveDecrypts = activeDecrypts;
      }
      await Future<void>.delayed(Duration.zero);
      activeDecrypts -= 1;
      return Uint8List(32);
    });
    when(
      () => entryCrypto.openMemberIndex(
        envelope: any(named: 'envelope'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((invocation) async {
      activeDecrypts += 1;
      if (activeDecrypts > maximumActiveDecrypts) {
        maximumActiveDecrypts = activeDecrypts;
      }
      await Future<void>.delayed(Duration.zero);
      activeDecrypts -= 1;
      final envelope = invocation.namedArguments[#envelope]! as Map;
      final scope = (envelope['descriptor'] as Map)['scope'] as Map;
      return _memberIndex('Entry ${scope['entryId']}');
    });
    when(
      () => remote.snapshot(
        vaultId: 'vault',
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer(
      (_) async => MemberSnapshotPage(
        snapshotBaseSequence: '100',
        items: List.generate(100, (index) => _head(_entryId(index))),
      ),
    );

    await service.synchronize(
      vaultId: 'vault',
      vaultKey: Uint8List(32),
      minimumMemberKeyGeneration: 1,
    );

    expect(maximumActiveDecrypts, 2);
  });

  test(
    'compact web MemberIndex contract parses every entry in a 539 item vault',
    () async {
      when(
        () => entryCrypto.openMemberIndex(
          envelope: any(named: 'envelope'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenAnswer((invocation) async {
        final envelope = invocation.namedArguments[#envelope]! as Map;
        final scope = (envelope['descriptor'] as Map)['scope'] as Map;
        final id = scope['entryId'] as String;
        return {
          'memberLabel': 'Imported $id',
          'entryType': 1,
          'searchFields': ['Imported $id', 'stripe.com'],
          'autofillDomains': ['stripe.com'],
          'iconReference':
              'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fstripe.png',
        };
      });
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((invocation) async {
        final cursor = invocation.namedArguments[#cursor] as String?;
        final offset = cursor == null ? 0 : int.parse(cursor);
        final end = (offset + 200).clamp(0, 539);
        return MemberSnapshotPage(
          snapshotBaseSequence: '539',
          items: List.generate(
            end - offset,
            (index) => _head(_entryId(offset + index)),
          ),
          nextCursor: end < 539 ? '$end' : null,
        );
      });

      final result = await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );

      final entries = service.entries('vault');
      expect(result.entryCount, 539);
      expect(entries, hasLength(539));
      expect(entries.every((entry) => !entry.corrupt), isTrue);
      expect(entries.last.memberLabel, contains(_entryId(538)));
      expect(
        entries.last.iconReference,
        'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fstripe.png',
      );
      expect(entries.last.autofillDomains, ['stripe.com']);
    },
  );

  test(
    'compact MemberIndex rejects unknown fields instead of widening protocol',
    () async {
      when(
        () => entryCrypto.openMemberIndex(
          envelope: any(named: 'envelope'),
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenAnswer(
        (_) async => {
          'memberLabel': 'Entry',
          'entryType': 1,
          'searchFields': const <String>[],
          'unexpected': true,
        },
      );
      when(
        () => remote.snapshot(
          vaultId: 'vault',
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer(
        (_) async => MemberSnapshotPage(
          snapshotBaseSequence: '1',
          items: [_head(_firstId)],
        ),
      );

      await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );

      expect(service.entries('vault').single.corrupt, isTrue);
    },
  );
}

String _entryId(int index) =>
    '33333333-3333-4333-8333-${index.toString().padLeft(12, '0')}';

Map<String, dynamic> _memberIndex(String label) => {
  'schema': 'palladin.member-index.v1',
  'entryType': 'credential',
  'memberLabel': label,
  'description': 'Postgres production database',
  'icon': {
    'kind': 'publicAsset',
    'assetId': '11111111-1111-4111-8111-111111111111',
    'revision': 1,
    'url': 'https://assets.palladin.io/example.png',
  },
  'color': null,
  'username': 'stage',
  'urlDomain': 'example.com',
  'customIndex': const <Object>[],
};

MemberSyncItemModel _head(String id, {int generation = 1}) {
  Map<String, dynamic> descriptor(
    int purpose, {
    Map<String, dynamic>? binding,
  }) => {
    'protocolVersion': 2,
    'cryptoSuiteId': 'palladin-vault-xchacha-v1',
    'purpose': purpose,
    'scope': {
      'organizationId': '11111111-1111-4111-8111-111111111111',
      'vaultId': 'vault',
      'entryId': id,
      'grantOrRequestId': null,
      'agentId': null,
      'memberId': null,
    },
    'resourceRevision': '1',
    'keyVersion': 1,
    'memberKeyGeneration': generation,
    'binding': binding ?? <String, dynamic>{},
  };
  return MemberSyncItemModel(
    entryId: id,
    kind: 'head',
    state: 'Active',
    currentRevision: '1',
    memberIndexRevision: '1',
    currentKeyVersion: 1,
    entryKey: {
      'descriptor': descriptor(8, binding: {'wrappingVaultKeyVersion': 1}),
      'encodedSuitePayload': 'ciphertext',
    },
    memberIndex: {
      'descriptor': descriptor(5),
      'encodedSuitePayload': 'ciphertext',
    },
  );
}
