import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_search_index_codec.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:sodium/sodium_sumo.dart' as ffi;

MemberSyncCacheState state({
  String sequence = '1',
  Map<String, dynamic> changes = const {},
}) => MemberSyncCacheState(
  sequence: sequence,
  memberVaultKey: const {},
  maximumObservedWallTime: DateTime.utc(2026),
  accessContext: MemberOfflineAccessContext.fromJson({
    'contextVersion': 1,
    'principalId': '11111111-1111-4111-8111-111111111111',
    'organizationId': '22222222-2222-4222-8222-222222222222',
    'organizationMembershipGeneration': '1',
    'vaultId': '33333333-3333-4333-8333-333333333333',
    'memberId': '44444444-4444-4444-8444-444444444444',
    'memberKeyGeneration': 1,
    'vaultKeyVersion': 1,
    'memberRecipientKeyVersion': 1,
    'memberRecipientKeyFingerprint': 'fingerprint',
    'offlinePolicy': '1h',
    'offlinePolicyVersion': 1,
    'issuedAt': '2026-11-18T10:00:00Z',
    'notAfter': '2026-11-18T11:00:00Z',
    ...changes,
  }),
);
MemberIndexEntry entry(String id, {String label = 'Private label'}) =>
    MemberIndexEntry(
      entryId: id,
      entryType: 1,
      memberLabel: label,
      searchFields: const ['hidden query'],
      revision: '9',
      currentKeyVersion: 3,
      state: MemberEntryState.archived,
      autofillDomains: const ['private.example'],
      iconReference: 'private-icon',
      username: 'private-user',
      corrupt: true,
    );
List<dynamic> chunks(String encoded) =>
    (jsonDecode(encoded) as Map)['chunks'] as List;
void main() {
  late MemberSearchIndexCodec codec;
  late Uint8List key;
  setUpAll(() async {
    final sodium = await ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(
        Platform.environment['PALLADIN_LIBSODIUM_PATH'] ?? 'libsodium.so',
      ),
    );
    codec = MemberSearchIndexCodec(sodiumLoader: () async => sodium);
  });
  setUp(() {
    key = Uint8List.fromList(List.generate(32, (i) => i));
  });
  test('roundtrips all metadata without plaintext in storage', () async {
    final sealed = await codec.seal(
      entries: [entry('entry-a')],
      state: state(),
      vaultKey: key,
    );
    for (final text in [
      'Private label',
      'hidden query',
      'private.example',
      'private-icon',
      'private-user',
      'entry-a',
    ]) {
      expect(sealed.encoded, isNot(contains(text)));
    }
    final result = (await codec.open(
      encoded: sealed.encoded,
      state: state(),
      vaultKey: key,
    )).entries.single;
    expect(result.entryId, 'entry-a');
    expect(result.entryType, 1);
    expect(result.memberLabel, 'Private label');
    expect(result.searchFields, ['hidden query']);
    expect(result.revision, '9');
    expect(result.currentKeyVersion, 3);
    expect(result.state, MemberEntryState.archived);
    expect(result.autofillDomains, ['private.example']);
    expect(result.iconReference, 'private-icon');
    expect(result.username, 'private-user');
    expect(result.corrupt, true);
  });
  test(
    'rejects every independent context mismatch and replayed sequence',
    () async {
      final sealed = await codec.seal(
        entries: [entry('a')],
        state: state(),
        vaultKey: key,
      );
      final changes = <String, dynamic>{
        'principalId': '99999999-9999-4999-8999-999999999999',
        'organizationId': '99999999-9999-4999-8999-999999999999',
        'organizationMembershipGeneration': '2',
        'vaultId': '99999999-9999-4999-8999-999999999999',
        'memberId': '99999999-9999-4999-8999-999999999999',
        'memberKeyGeneration': 2,
        'vaultKeyVersion': 2,
        'memberRecipientKeyVersion': 2,
        'memberRecipientKeyFingerprint': 'other',
        'offlinePolicy': '4h',
        'offlinePolicyVersion': 2,
        'issuedAt': '2026-11-18T10:01:00Z',
        'notAfter': '2026-11-18T12:00:00Z',
      };
      for (final change in changes.entries) {
        await expectLater(
          codec.open(
            encoded: sealed.encoded,
            state: state(changes: {change.key: change.value}),
            vaultKey: key,
          ),
          throwsA(isA<MemberSearchIndexException>()),
          reason: change.key,
        );
      }
      await expectLater(
        codec.open(
          encoded: sealed.encoded,
          state: state(sequence: '2'),
          vaultKey: key,
        ),
        throwsA(isA<MemberSearchIndexException>()),
      );
      await expectLater(
        codec.open(
          encoded: sealed.encoded,
          state: state(),
          vaultKey: Uint8List(32),
        ),
        throwsA(isA<MemberSearchIndexException>()),
      );
    },
  );
  test('rejects missing reordered replaced and tampered chunks', () async {
    final sealed = await codec.seal(
      entries: List.generate(30, (i) => entry('$i')),
      state: state(),
      vaultKey: key,
    );
    final other = await codec.seal(
      entries: [entry('replacement')],
      state: state(),
      vaultKey: key,
    );
    for (final mutation in <void Function(List<dynamic>)>[
      (c) => c.removeLast(),
      (c) {
        final first = c[0];
        c[0] = c[1];
        c[1] = first;
      },
      (c) => c[0] = chunks(other.encoded)[0],
      (c) => c[0] = 'AAAA',
    ]) {
      final value = jsonDecode(sealed.encoded) as Map<String, dynamic>;
      mutation(value['chunks'] as List);
      await expectLater(
        codec.open(encoded: jsonEncode(value), state: state(), vaultKey: key),
        throwsA(isA<MemberSearchIndexException>()),
      );
    }
  });
  test('manifest tampering and old changed chunks are rejected', () async {
    final original = await codec.seal(
      entries: [entry('a')],
      state: state(),
      vaultKey: key,
    );
    final nextState = state(sequence: '2');
    final updated = await codec.seal(
      entries: [entry('a', label: 'Updated')],
      state: nextState,
      vaultKey: key,
      previous: original,
    );
    final replay = jsonDecode(updated.encoded) as Map<String, dynamic>;
    replay['chunks'] = chunks(original.encoded);
    await expectLater(
      codec.open(encoded: jsonEncode(replay), state: nextState, vaultKey: key),
      throwsA(isA<MemberSearchIndexException>()),
    );
    final tampered = jsonDecode(updated.encoded) as Map<String, dynamic>;
    tampered['manifest'] = (jsonDecode(original.encoded) as Map)['manifest'];
    await expectLater(
      codec.open(
        encoded: jsonEncode(tampered),
        state: nextState,
        vaultKey: key,
      ),
      throwsA(isA<MemberSearchIndexException>()),
    );
  });
  test('empty index is valid', () async {
    final sealed = await codec.seal(entries: [], state: state(), vaultKey: key);
    expect(
      (await codec.open(
        encoded: sealed.encoded,
        state: state(),
        vaultKey: key,
      )).entries,
      isEmpty,
    );
  });
  test(
    'partial update and delete reuse only unchanged buckets across leases',
    () async {
      final entries = List.generate(30, (i) => entry('$i'));
      final sealed = await codec.seal(
        entries: entries,
        state: state(),
        vaultKey: key,
      );
      final opened = await codec.open(
        encoded: sealed.encoded,
        state: state(),
        vaultKey: key,
      );
      final nextState = state(
        sequence: '2',
        changes: {'issuedAt': '2026-11-18T10:01:00Z'},
      );
      final updated = await codec.seal(
        entries: [
          entry('0', label: 'Changed'),
          ...entries.skip(2),
        ],
        state: nextState,
        vaultKey: key,
        previous: opened,
      );
      final before = chunks(sealed.encoded), after = chunks(updated.encoded);
      expect(
        List.generate(
          16,
          (i) => before[i] == after[i],
        ).where((same) => same).length,
        greaterThanOrEqualTo(14),
      );
      final result = await codec.open(
        encoded: updated.encoded,
        state: nextState,
        vaultKey: key,
      );
      expect(result.entries.length, 29);
      expect(result.entries.any((e) => e.entryId == '1'), false);
      expect(
        result.entries.singleWhere((e) => e.entryId == '0').memberLabel,
        'Changed',
      );
      final rotated = await codec.seal(
        entries: result.entries,
        state: nextState,
        vaultKey: Uint8List(32),
        previous: updated,
      );
      expect(
        List.generate(16, (i) => chunks(rotated.encoded)[i] == after[i]),
        everyElement(false),
      );
      expect(
        (await codec.open(
          encoded: rotated.encoded,
          state: nextState,
          vaultKey: Uint8List(32),
        )).entries.length,
        29,
      );
    },
  );
  test('rebind renews only manifest and keeps immutable metadata', () async {
    final fields = ['original'];
    final domains = ['original.example'];
    final sealed = await codec.seal(
      entries: [
        MemberIndexEntry(
          entryId: 'a',
          entryType: 1,
          memberLabel: 'label',
          searchFields: fields,
          revision: '1',
          state: MemberEntryState.active,
          autofillDomains: domains,
        ),
      ],
      state: state(),
      vaultKey: key,
    );
    fields[0] = 'changed';
    domains[0] = 'changed.example';
    expect(sealed.entries.single.searchFields, ['original']);
    expect(sealed.entries.single.autofillDomains, ['original.example']);
    expect(
      () => sealed.entries.single.searchFields.add('bad'),
      throwsUnsupportedError,
    );
    expect(
      await codec.rebind(previous: sealed, state: state(), vaultKey: key),
      same(sealed),
    );
    final renewed = state(
      sequence: '2',
      changes: {
        'issuedAt': '2026-11-18T10:01:00Z',
        'notAfter': '2026-11-18T11:01:00Z',
      },
    );
    final rebound = (await codec.rebind(
      previous: sealed,
      state: renewed,
      vaultKey: key,
    ))!;
    expect(rebound.entries, same(sealed.entries));
    expect(chunks(rebound.encoded), chunks(sealed.encoded));
    expect(rebound.encoded, isNot(sealed.encoded));
    expect(
      (await codec.open(
        encoded: rebound.encoded,
        state: renewed,
        vaultKey: key,
      )).entries.single.searchFields,
      ['original'],
    );
    await expectLater(
      codec.open(encoded: rebound.encoded, state: state(), vaultKey: key),
      throwsA(isA<MemberSearchIndexException>()),
    );
    await expectLater(
      codec.open(encoded: sealed.encoded, state: renewed, vaultKey: key),
      throwsA(isA<MemberSearchIndexException>()),
    );
    expect(
      await codec.rebind(
        previous: sealed,
        state: state(),
        vaultKey: Uint8List(32),
      ),
      isNull,
    );
    expect(
      await codec.rebind(
        previous: sealed,
        state: state(changes: {'memberKeyGeneration': 2}),
        vaultKey: key,
      ),
      isNull,
    );
  });
  test('rejects duplicate entries and excessive metadata', () async {
    await expectLater(
      codec.seal(
        entries: [entry('a'), entry('a')],
        state: state(),
        vaultKey: key,
      ),
      throwsA(isA<MemberSearchIndexException>()),
    );
    await expectLater(
      codec.seal(
        entries: [entry('a', label: 'x' * (4 * 1024 * 1024))],
        state: state(),
        vaultKey: key,
      ),
      throwsA(isA<MemberSearchIndexException>()),
    );
  });
}
