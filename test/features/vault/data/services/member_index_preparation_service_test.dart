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
      when(() => vaults.loadForMemberIndex(any())).thenAnswer((_) async {
        await pending.future;
        return [_vault('first'), _vault('second')];
      });

      final first = service.prepare(Uint8List(32));
      final second = service.prepare(Uint8List(32));

      expect(identical(first, second), isTrue);
      pending.complete();
      final results = await Future.wait([first, second]);

      expect(results.first.map((vault) => vault.id), ['first', 'second']);
      verify(() => vaults.loadForMemberIndex(any())).called(1);
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

  test(
    'mutation preparation queues one fresh pass after active work',
    () async {
      final first = Completer<List<VaultEntity>>();
      final trailing = Completer<List<VaultEntity>>();
      var calls = 0;
      when(() => vaults.loadForMemberIndex(any())).thenAnswer((_) {
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
      verify(() => vaults.loadForMemberIndex(any())).called(2);
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
