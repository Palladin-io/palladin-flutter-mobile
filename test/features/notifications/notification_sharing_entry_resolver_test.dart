import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_sharing_entry_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/entry_sharing_notification_target.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _Index extends Mock implements MemberEntryListLoader {}

void main() {
  const target = (vaultId: 'vault', entryId: 'entry');
  const owner = MemberSyncSessionAuthority(
    principalId: 'account',
    organizationId: 'org',
    organizationMembershipGeneration: '1',
    offlinePolicy: 'disabled',
    offlinePolicyVersion: 1,
  );
  MemberIndexEntry entry({
    MemberEntryState state = MemberEntryState.active,
    bool corrupt = false,
    int type = 1,
  }) => MemberIndexEntry(
    entryId: 'entry',
    entryType: type,
    memberLabel: 'Local label',
    searchFields: const [],
    revision: '7',
    currentKeyVersion: 3,
    state: state,
    corrupt: corrupt,
  );
  late _Index index;
  late bool current;
  late Future<MemberSyncSessionAuthority> Function() authority;
  late NotificationSharingEntryResolver resolver;
  final privateKey = Uint8List(32);
  Future<List<MemberIndexEntry>> load() =>
      index.load(vaultId: 'vault', memberPrivateKey: privateKey);
  setUp(() {
    index = _Index();
    current = true;
    authority = () async => owner;
    when(load).thenAnswer((_) async => [entry()]);
    resolver = NotificationSharingEntryResolver(
      entries: index,
      readAuthority: () => authority(),
    );
  });
  Future<EntryEntity?> resolve() => resolver.resolve(
    target: target,
    principalId: 'account',
    memberPrivateKey: privateKey,
    isCurrent: () => current,
  );

  for (final state in [MemberEntryState.active, MemberEntryState.archived]) {
    test('resolves $state only from exact local Vault and Entry', () async {
      when(load).thenAnswer((_) async => [entry(state: state)]);
      final result = await resolve();
      expect(result!.id, 'entry');
      expect(result.vaultId, 'vault');
      expect(result.label, 'Local label');
      expect(result.currentRevision, '7');
      expect(result.currentKeyVersion, 3);
      expect(result.lifecycleState, state);
      verify(load).called(1);
    });
  }
  for (final condition in [
    'missing',
    'deleted',
    'unknown',
    'corrupt',
    'duplicate',
    'type',
  ]) {
    test('rejects $condition local target', () async {
      when(load).thenAnswer(
        (_) async => switch (condition) {
          'missing' => [],
          'deleted' => [entry(state: MemberEntryState.deleted)],
          'unknown' => [entry(state: MemberEntryState.unknown)],
          'corrupt' => [entry(corrupt: true)],
          'duplicate' => [entry(), entry()],
          _ => [entry(type: 999)],
        },
      );
      expect(await resolve(), isNull);
    });
  }
  for (final phase in ['before', 'authority', 'index', 'final-authority']) {
    test('late $phase cannot return local presentation', () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      var authorityCalls = 0;
      authority = () async {
        authorityCalls++;
        if ((phase == 'authority' && authorityCalls == 1) ||
            (phase == 'final-authority' && authorityCalls == 2)) {
          entered.complete();
          await gate.future;
        }
        return owner;
      };
      if (phase == 'index') {
        when(load).thenAnswer((_) async {
          entered.complete();
          await gate.future;
          return [entry()];
        });
      }
      if (phase == 'before') current = false;
      final pending = resolve();
      if (phase != 'before') await entered.future;
      current = false;
      gate.complete();
      expect(await pending, isNull);
      if (phase == 'before' || phase == 'authority') verifyNever(load);
    });
  }
  for (final change in ['principal', 'organization', 'generation']) {
    test('changed $change authority refuses navigation', () async {
      var calls = 0;
      authority = () async => ++calls == 1
          ? owner
          : MemberSyncSessionAuthority(
              principalId: change == 'principal' ? 'other' : 'account',
              organizationId: change == 'organization' ? 'other' : 'org',
              organizationMembershipGeneration: change == 'generation'
                  ? '2'
                  : '1',
              offlinePolicy: 'disabled',
              offlinePolicyVersion: 1,
            );
      expect(await resolve(), isNull);
    });
  }
  test(
    'index failure returns unavailable without another destination',
    () async {
      when(load).thenThrow(StateError('synthetic'));
      expect(await resolve(), isNull);
    },
  );
  test('receipt destination never uses a supplied URL or another type', () {
    InboxNotification item(String type, Map<String, dynamic> metadata) =>
        InboxNotification(
          id: 'n',
          type: type,
          category: NotificationCategory.update,
          titleKey: '',
          metadata: metadata,
          actionState: NotificationActionState.none,
          occurredAt: DateTime(2026),
        );
    const metadata = {
      'vaultId': 'vault',
      'entryId': 'entry',
      'actionDeepLink': 'https://untrusted.invalid/other',
    };
    expect(
      entrySharingNotificationTarget(item('entry_share_received', metadata)),
      target,
    );
    expect(entrySharingNotificationTarget(item('future', metadata)), isNull);
    expect(
      entrySharingNotificationTarget(
        item('entry_share_received', const {'vaultId': 'vault'}),
      ),
      isNull,
    );
  });
}
