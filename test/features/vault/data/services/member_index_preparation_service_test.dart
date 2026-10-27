import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_index_preparation_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';

class _Vaults extends Mock implements MemberVaultListLoader {}

class _Entries extends Mock implements MemberEntryListLoader {}

void main() {
  late _Vaults vaults;
  late _Entries entries;
  late MemberIndexPreparationService service;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    vaults = _Vaults();
    entries = _Entries();
    service = MemberIndexPreparationService(vaults: vaults, entries: entries);
    when(
      () => entries.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => const []);
  });

  test(
    'concurrent dashboard and AutoFill preparation shares all work',
    () async {
      final pending = Completer<void>();
      when(
        () => vaults.loadForMemberIndex(any(), ensureFresh: false),
      ).thenAnswer((_) async {
        await pending.future;
        return [_vault('first'), _vault('second')];
      });

      final first = service.prepare(Uint8List(32));
      final second = service.prepare(Uint8List(32));

      expect(identical(first, second), isTrue);
      pending.complete();
      final results = await Future.wait([first, second]);

      expect(results.first.map((vault) => vault.id), ['first', 'second']);
      verify(
        () => vaults.loadForMemberIndex(any(), ensureFresh: false),
      ).called(1);
      verify(
        () => entries.load(
          vaultId: 'first',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).called(1);
      verify(
        () => entries.load(
          vaultId: 'second',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).called(1);
    },
  );

  test('prepares eight Vaults with bounded overlapping sync', () async {
    final items = List.generate(8, (i) => _vault('vault-$i'));
    when(
      () => vaults.loadForMemberIndex(any(), ensureFresh: false),
    ).thenAnswer((_) async => items);
    var active = 0;
    var peak = 0;
    var calls = 0;
    when(
      () => entries.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async {
      calls++;
      active++;
      if (active > peak) peak = active;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      active--;
      return const [];
    });
    final watch = Stopwatch()..start();
    final result = await service.prepare(Uint8List(32));
    watch.stop();
    // Synthetic transport delay, not device latency or a CI timing threshold.
    // ignore: avoid_print
    print(
      '8 Vaults / 40ms loader: ${watch.elapsedMilliseconds}ms; peak=$peak; calls=$calls',
    );
    expect(result, items);
    expect(calls, 8);
    expect(peak, inInclusiveRange(2, 4));
  });

  test('lock drains active loads and prevents the next Vault batch', () async {
    final pending = Completer<void>();
    final keys = <Uint8List>[];
    when(
      () => vaults.loadForMemberIndex(any(), ensureFresh: false),
    ).thenAnswer((_) async => List.generate(8, (i) => _vault('vault-$i')));
    when(
      () => entries.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((invocation) async {
      keys.add(invocation.namedArguments[#memberPrivateKey] as Uint8List);
      await pending.future;
      return const [];
    });
    final operation = service.prepare(Uint8List.fromList(List.filled(32, 7)));
    final failure = expectLater(operation, throwsA(isA<Exception>()));
    await Future<void>.delayed(Duration.zero);
    final started = keys.length;
    service.lock();
    pending.complete();
    await failure;
    expect(started, inInclusiveRange(2, 4));
    expect(keys, hasLength(started));
    expect(keys.every((key) => key.every((byte) => byte == 0)), isTrue);
  });

  test(
    'failed batch drains sibling loads before wiping its private key',
    () async {
      final pending = Completer<void>();
      final keys = <Uint8List>[];
      var completed = false;
      when(
        () => vaults.loadForMemberIndex(any(), ensureFresh: false),
      ).thenAnswer((_) async => List.generate(8, (i) => _vault('vault-$i')));
      when(
        () => entries.load(
          vaultId: any(named: 'vaultId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        keys.add(invocation.namedArguments[#memberPrivateKey] as Uint8List);
        if (invocation.namedArguments[#vaultId] == 'vault-0') {
          throw StateError('synthetic sync failure');
        }
        await pending.future;
        expect(keys.last.every((byte) => byte == 7), isTrue);
        return const [];
      });
      final operation = service.prepare(Uint8List.fromList(List.filled(32, 7)));
      final failure = expectLater(operation, throwsStateError).then((_) {
        completed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      pending.complete();
      await failure;
      expect(keys, hasLength(4));
      expect(keys.every((key) => key.every((byte) => byte == 0)), isTrue);
    },
  );

  test(
    'mutation preparation queues one fresh pass after active work',
    () async {
      final first = Completer<List<VaultEntity>>();
      final trailing = Completer<List<VaultEntity>>();
      var calls = 0;
      when(
        () => vaults.loadForMemberIndex(
          any(),
          ensureFresh: any(named: 'ensureFresh'),
        ),
      ).thenAnswer((invocation) {
        calls += 1;
        return calls == 1 ? first.future : trailing.future;
      });

      final active = service.prepare(Uint8List(32));
      final fresh = service.prepare(Uint8List(32), ensureFresh: true);
      final sameFresh = service.prepare(Uint8List(32), ensureFresh: true);

      expect(identical(fresh, sameFresh), isTrue);
      first.complete([_vault('before')]);
      await active;
      expect(calls, 2);

      trailing.complete([_vault('after')]);
      expect((await fresh).single.id, 'after');
      await sameFresh;
      verify(
        () => vaults.loadForMemberIndex(any(), ensureFresh: false),
      ).called(1);
      verify(
        () => vaults.loadForMemberIndex(any(), ensureFresh: true),
      ).called(1);
    },
  );
}

VaultEntity _vault(String id) => VaultEntity(
  id: id,
  name: id,
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 0,
  activeGrantCount: 0,
  memberCount: 1,
);
