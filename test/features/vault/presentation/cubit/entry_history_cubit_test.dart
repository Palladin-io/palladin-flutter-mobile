import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_history_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_history_cubit.dart';

class _HistoryService extends Mock implements EntryHistoryService {}

void main() {
  late _HistoryService service;
  late EntryHistoryCubit cubit;
  final entry = EntryEntity(
    id: 'entry-id',
    vaultId: 'vault-id',
    label: 'Entry',
    type: EntryType.key,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  final version = EntryHistoryVersion(
    revision: '7',
    changedAt: DateTime.utc(2026),
    changedByType: 'member',
    changedById: '12345678-1234-1234-1234-123456789012',
    operation: 'updated',
    encrypted: const {'revision': '7'},
  );

  setUpAll(() {
    registerFallbackValue(entry);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    service = _HistoryService();
    cubit = EntryHistoryCubit(service);
  });

  tearDown(() => cubit.close());

  test('does not fetch until History is explicitly opened', () {
    expect(cubit.state.status, EntryHistoryStatus.initial);
    verifyNever(() => service.loadPage(any()));
  });

  test('open is idempotent and keeps history paging bounded', () async {
    when(() => service.loadPage(entry)).thenAnswer(
      (_) async => EntryHistoryPage(items: [version], nextCursor: '7'),
    );
    await cubit.open(entry);
    await cubit.open(entry);
    expect(cubit.state.items, [version]);
    verify(() => service.loadPage(entry)).called(1);
  });

  test(
    'invalidating after an Entry update reloads History on next open',
    () async {
      final updated = EntryEntity(
        id: entry.id,
        vaultId: entry.vaultId,
        label: 'Updated Entry',
        type: entry.type,
        createdAt: entry.createdAt,
        updatedAt: DateTime.utc(2026, 2),
        currentRevision: '8',
      );
      final updatedVersion = EntryHistoryVersion(
        revision: '8',
        changedAt: DateTime.utc(2026, 2),
        changedByType: 'member',
        changedById: version.changedById,
        operation: 'updated',
        encrypted: const {'revision': '8'},
      );
      when(() => service.loadPage(entry)).thenAnswer(
        (_) async => EntryHistoryPage(items: [version], nextCursor: null),
      );
      when(() => service.loadPage(updated)).thenAnswer(
        (_) async =>
            EntryHistoryPage(items: [updatedVersion], nextCursor: null),
      );

      await cubit.open(entry);
      cubit.invalidate();
      await cubit.open(updated);

      expect(cubit.state.items, [updatedVersion]);
      verify(() => service.loadPage(entry)).called(1);
      verify(() => service.loadPage(updated)).called(1);
    },
  );

  test(
    'corrupt selected version clears plaintext but keeps encrypted rows',
    () async {
      when(() => service.loadPage(entry)).thenAnswer(
        (_) async => EntryHistoryPage(items: [version], nextCursor: null),
      );
      when(
        () => service.reveal(
          entry: entry,
          version: version,
          privateKey: any(named: 'privateKey'),
        ),
      ).thenThrow(const FormatException('corrupt'));
      await cubit.open(entry);
      await cubit.reveal(
        entry: entry,
        version: version,
        privateKey: Uint8List(32),
      );
      expect(cubit.state.status, EntryHistoryStatus.ready);
      expect(cubit.state.failure, EntryHistoryFailure.reveal);
      expect(cubit.state.selected, isNull);
      expect(cubit.state.items, [version]);
    },
  );

  test('lock clears the selected decrypted snapshot in place', () async {
    final secret = <String, dynamic>{'memberLabel': 'old'};
    final payload = <String, dynamic>{'value': 'plaintext'};
    final selected = CanonicalEntryHistorySnapshot(
      secret: secret,
      payload: payload,
    );
    when(
      () => service.reveal(
        entry: entry,
        version: version,
        privateKey: any(named: 'privateKey'),
      ),
    ).thenAnswer((_) async => selected);
    final ownerKey = Uint8List.fromList(List<int>.filled(32, 7));
    final borrowedCopy = Uint8List.fromList(ownerKey);
    await cubit.reveal(
      entry: entry,
      version: version,
      privateKey: borrowedCopy,
    );
    expect(borrowedCopy, everyElement(0));
    expect(ownerKey, everyElement(7));
    cubit.clearSensitiveState(keepItems: true);
    expect(secret, isEmpty);
    expect(payload, isEmpty);
    expect(cubit.state.selected, isNull);
  });

  test('hide clears plaintext and keeps the loaded history page', () async {
    final selected = CanonicalEntryHistorySnapshot(
      secret: {'memberLabel': 'old'},
      payload: {'value': 'plaintext'},
    );
    when(() => service.loadPage(entry)).thenAnswer(
      (_) async => EntryHistoryPage(items: [version], nextCursor: null),
    );
    when(
      () => service.reveal(
        entry: entry,
        version: version,
        privateKey: any(named: 'privateKey'),
      ),
    ).thenAnswer((_) async => selected);
    await cubit.open(entry);
    await cubit.reveal(
      entry: entry,
      version: version,
      privateKey: Uint8List(32),
    );

    cubit.hideSelected();

    expect(cubit.state.status, EntryHistoryStatus.ready);
    expect(cubit.state.items, [version]);
    expect(cubit.state.selected, isNull);
    expect(selected.secret, isEmpty);
    expect(selected.payload, isEmpty);
  });

  test(
    'restore publishes the new current Entry and wipes historical plaintext',
    () async {
      final selected = CanonicalEntryHistorySnapshot(
        secret: {'memberLabel': 'old'},
        payload: {'value': 'plaintext'},
      );
      final updated = EntryEntity(
        id: entry.id,
        vaultId: entry.vaultId,
        label: 'old',
        type: EntryType.key,
        createdAt: entry.createdAt,
        updatedAt: DateTime.utc(2026, 2),
        currentRevision: '8',
      );
      when(
        () => service.reveal(
          entry: entry,
          version: version,
          privateKey: any(named: 'privateKey'),
        ),
      ).thenAnswer((_) async => selected);
      when(
        () => service.restore(
          entry: entry,
          selected: selected,
          privateKey: any(named: 'privateKey'),
        ),
      ).thenAnswer((_) async => updated);
      final key = Uint8List(32);
      await cubit.reveal(entry: entry, version: version, privateKey: key);
      await cubit.restore(entry: entry, privateKey: key);
      expect(cubit.state.updatedEntry?.currentRevision, '8');
      expect(selected.payload, isEmpty);
      expect(selected.secret, isEmpty);
    },
  );
}
