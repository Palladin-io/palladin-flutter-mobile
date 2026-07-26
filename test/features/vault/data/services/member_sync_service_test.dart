import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';

const _oldId = '33333333-3333-4333-8333-333333333330';
const _firstId = '33333333-3333-4333-8333-333333333331';
const _secondId = '33333333-3333-4333-8333-333333333332';
const _newId = '33333333-3333-4333-8333-333333333339';

class _Remote extends Mock implements MemberSyncRemote {}

class _Envelopes extends Mock implements VaultEnvelopeCryptography {}

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

void main() {
  late _Remote remote;
  late _Envelopes envelopes;
  late _MemoryCache cache;
  late MemberSyncService service;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(VaultAadProfile.memberIndex);
    registerFallbackValue(
      const VaultEnvelopeExpectations(
        aadContext: <String, Object?>{},
        minimumMemberKeyGeneration: 0,
      ),
    );
  });

  setUp(() {
    remote = _Remote();
    envelopes = _Envelopes();
    cache = _MemoryCache();
    service = MemberSyncService(
      remote: remote,
      cache: cache,
      envelopes: envelopes,
    );
    when(
      () => envelopes.decrypt(
        profile: VaultAadProfile.entryKeyWrapper,
        envelope: any(named: 'envelope'),
        key: any(named: 'key'),
        expected: any(named: 'expected'),
      ),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => envelopes.decrypt(
        profile: VaultAadProfile.memberIndex,
        envelope: any(named: 'envelope'),
        key: any(named: 'key'),
        expected: any(named: 'expected'),
      ),
    ).thenAnswer((invocation) async {
      final envelope = invocation.namedArguments[#envelope]! as Map;
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'entryType': 1,
            'memberLabel': 'Database ${envelope['entryId']}',
            'searchFields': ['stage', 'postgres'],
          }),
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

      final result = await service.synchronize(
        vaultId: 'vault',
        vaultKey: Uint8List(32),
        minimumMemberKeyGeneration: 1,
      );

      expect(result.sequence, '7');
      expect(result.entryCount, 2);
      expect(result.usedSnapshot, isTrue);
      expect(service.search('postgres', vaultId: 'vault').length, 2);
      service.lock();
      expect(service.search('postgres', vaultId: 'vault'), isEmpty);
    },
  );

  test(
    'resetRequired discards incremental path and installs a snapshot',
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
        () => envelopes.decrypt(
          profile: VaultAadProfile.memberIndex,
          envelope: any(named: 'envelope'),
          key: any(named: 'key'),
          expected: any(named: 'expected'),
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
      () => envelopes.decrypt(
        profile: any(named: 'profile'),
        envelope: any(named: 'envelope'),
        key: any(named: 'key'),
        expected: any(named: 'expected'),
      ),
    ).thenAnswer((invocation) async {
      activeDecrypts += 1;
      if (activeDecrypts > maximumActiveDecrypts) {
        maximumActiveDecrypts = activeDecrypts;
      }
      await Future<void>.delayed(Duration.zero);
      activeDecrypts -= 1;
      final profile = invocation.namedArguments[#profile] as VaultAadProfile;
      if (profile == VaultAadProfile.entryKeyWrapper) return Uint8List(32);
      final envelope = invocation.namedArguments[#envelope]! as Map;
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'entryType': 1,
            'memberLabel': 'Entry ${envelope['entryId']}',
            'searchFields': const <String>[],
          }),
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
}

String _entryId(int index) =>
    '33333333-3333-4333-8333-${index.toString().padLeft(12, '0')}';

MemberSyncItemModel _head(String id) {
  final header = {
    'protocolVersion': 2,
    'algorithmSuite': 1,
    'resourceKind': 2,
    'projectionKind': 2,
    'resourceRevision': '1',
    'keyVersion': 1,
    'memberKeyGeneration': 1,
    'nonce': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  };
  return MemberSyncItemModel(
    entryId: id,
    kind: 'head',
    state: 'Active',
    currentRevision: '1',
    memberIndexRevision: '1',
    currentKeyVersion: 1,
    entryKey: {
      'organizationId': '11111111-1111-4111-8111-111111111111',
      'vaultId': '22222222-2222-4222-8222-222222222222',
      'entryId': id,
      'wrapperRevision': '1',
      'keyVersion': 1,
      'memberKeyGeneration': 1,
      'wrappingKeyVersion': 1,
      'header': header,
      'wrappedEntryDekByVk': 'ciphertext',
    },
    memberIndex: {
      'organizationId': '11111111-1111-4111-8111-111111111111',
      'vaultId': '22222222-2222-4222-8222-222222222222',
      'entryId': id,
      'memberIndexRevision': '1',
      'header': header,
      'ciphertext': 'ciphertext',
    },
  );
}
