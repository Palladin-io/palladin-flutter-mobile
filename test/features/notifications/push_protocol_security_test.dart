import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/domain/repositories/agents_repository.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/data/services/push_event_deduplicator.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/push_message.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/push_navigation_cubit.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_member.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_members_repository.dart';

class _Index extends Mock implements MemberIndexReader {}

class _Repository extends Mock implements NotificationCenterRepository {}

class _Grants extends Mock implements GrantsRepository {}

class _Agents extends Mock implements AgentsRepository {}

class _Members extends Mock implements VaultMembersRepository {}

final _occurredAt = DateTime.utc(2026, 7, 26, 20);

PushMessage _push() => PushMessage(
  type: PushNotificationType.credentialStale,
  category: 'update',
  subjectId: 'subject',
  occurredAt: _occurredAt,
);

InboxNotification _inbox({
  String id = 'notification',
  String subjectId = 'subject',
  String type = 'credential_stale',
  Map<String, dynamic>? metadata,
}) => InboxNotification(
  id: id,
  subjectId: subjectId,
  type: type,
  category: NotificationCategory.update,
  titleKey: 'credential_stale',
  metadata: metadata ?? const {},
  actionState: NotificationActionState.none,
  occurredAt: _occurredAt,
);

final _vault = VaultEntity(
  id: 'vault',
  name: 'Personal',
  grantMode: GrantMode.granular,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  entryCount: 1,
  activeGrantCount: 0,
  memberCount: 1,
);

void main() {
  test(
    'deduplicates foreground/background delivery with a bounded session set',
    () {
      final dedupe = PushEventDeduplicator(capacity: 2);
      expect(dedupe.accept(_push()), isTrue);
      expect(dedupe.accept(_push()), isFalse);
      final second = PushMessage(
        type: PushNotificationType.credentialStale,
        category: 'update',
        subjectId: 'second',
        occurredAt: _occurredAt,
      );
      final third = PushMessage(
        type: PushNotificationType.credentialStale,
        category: 'update',
        subjectId: 'third',
        occurredAt: _occurredAt,
      );
      expect(dedupe.accept(second), isTrue);
      expect(dedupe.accept(third), isTrue);
      expect(dedupe.accept(_push()), isTrue);
    },
  );

  test(
    'locked and cross-account references stay generic without index access',
    () async {
      final index = _Index();
      final resolver = NotificationPresentationResolver(index: index);
      final source = _inbox(
        metadata: {
          'vaultId': 'foreign',
          'entryId': 'entry',
          'vaultName': 'forged',
          'entryLabel': 'forged',
          'actionDeepLink': '/vaults/foreign',
        },
      );

      final locked = await resolver.resolve(
        items: [source],
        unlocked: false,
        activeAccountId: 'account',
        activeOrganizationId: 'organization',
        activeVaults: [_vault],
      );
      final foreign = await resolver.resolve(
        items: [source],
        unlocked: true,
        activeAccountId: 'account',
        activeOrganizationId: 'organization',
        activeVaults: [_vault],
      );

      expect(locked.single.metadata['entryLabel'], isNull);
      expect(foreign.single.metadata['vaultId'], isNull);
      verifyNever(() => index.entries(any()));
      verifyNever(() => index.waitForCurrent(any()));
    },
  );

  test(
    'unlocked resolver uses exact vault index and deleted entry is generic',
    () async {
      final index = _Index();
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'deleted',
          entryType: 1,
          memberLabel: 'Must not render',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.deleted,
        ),
      ]);
      final resolved = await NotificationPresentationResolver(index: index)
          .resolve(
            items: [
              _inbox(
                metadata: const {'vaultId': 'vault', 'entryId': 'deleted'},
              ),
            ],
            unlocked: true,
            activeAccountId: 'account',
            activeOrganizationId: 'organization',
            activeVaults: [_vault],
          );
      expect(resolved.single.metadata['vaultName'], 'Personal');
      expect(resolved.single.metadata['entryLabel'], isNull);
      verify(() => index.entries('vault')).called(1);
    },
  );

  test(
    'grant notifications resolve decrypted reason and actor from authoritative data',
    () async {
      final index = _Index();
      final grants = _Grants();
      final agents = _Agents();
      final members = _Members();
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Production token',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      when(() => agents.listAgents()).thenAnswer(
        (_) async => [
          Agent(
            agentId: 'agent',
            name: 'Deploy bot',
            status: AgentStatus.active,
            publicKeySuffix: 'suffix',
            createdAt: DateTime.utc(2026, 8, 1),
          ),
        ],
      );
      when(() => grants.getGrant('vault', 'grant')).thenAnswer(
        (_) async => Grant(
          id: 'grant',
          vaultId: 'vault',
          agentId: 'agent',
          status: GrantStatus.active,
          scope: GrantScope.granular,
          entryId: 'entry',
          reason: 'Deploy release',
          createdBy: 'member',
          createdAt: DateTime.utc(2026, 8, 7),
        ),
      );
      when(() => members.list('vault')).thenAnswer(
        (_) async => [
          VaultMember(
            id: 'member',
            name: 'Alice',
            addedAt: DateTime.utc(2026, 1, 1),
            status: VaultMemberStatus.active,
          ),
        ],
      );

      final resolved =
          await NotificationPresentationResolver(
            index: index,
            grants: grants,
            agents: agents,
            vaultMembers: members,
          ).resolve(
            items: [
              _inbox(
                type: 'grant_approved',
                metadata: const {
                  'vaultId': 'vault',
                  'entryId': 'entry',
                  'grantId': 'grant',
                  'agentId': 'agent',
                  'reason': 'FORGED',
                  'actorName': 'FORGED',
                },
              ),
              _inbox(
                id: 'pending-notification',
                type: 'grant_pending',
                metadata: const {
                  'vaultId': 'vault',
                  'entryId': 'entry',
                  'grantId': 'grant',
                  'agentId': 'agent',
                  'reason': 'FORGED',
                },
              ),
            ],
            unlocked: true,
            activeAccountId: 'member',
            activeOrganizationId: 'organization',
            activeVaults: [_vault],
          );

      expect(resolved[0].metadata['entryLabel'], 'Production token');
      expect(resolved[0].metadata['grantType'], 'granular');
      expect(resolved[0].metadata['entryId'], 'entry');
      expect(resolved[0].metadata['agentName'], 'Deploy bot');
      expect(resolved[0].metadata['reason'], 'Deploy release');
      expect(resolved[0].metadata['actorName'], 'Alice');
      expect(resolved[1].metadata['reason'], 'Deploy release');
      expect(resolved[1].metadata['actorName'], isNull);
    },
  );

  for (final nextState in [MemberEntryState.active, MemberEntryState.deleted]) {
    test('Entry navigation waits for in-flight $nextState sync', () async {
      final index = _Index();
      final sync = Completer<void>();
      var current = const MemberIndexEntry(
        entryId: 'entry',
        entryType: 1,
        memberLabel: 'Previous',
        searchFields: [],
        revision: '1',
        state: MemberEntryState.active,
      );
      when(() => index.waitForCurrent('vault')).thenAnswer((_) => sync.future);
      when(() => index.entries('vault')).thenAnswer((_) => [current]);
      final resolver = NotificationPresentationResolver(index: index);
      final pending = Future.sync(
        () => resolver.resolveEntry('vault', 'entry'),
      );
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => index.entries('vault'));
      current = MemberIndexEntry(
        entryId: 'entry',
        entryType: 1,
        memberLabel: 'Current',
        searchFields: [],
        revision: '2',
        currentKeyVersion: 3,
        state: nextState,
      );
      sync.complete();
      final entry = await pending;
      if (nextState == MemberEntryState.deleted) {
        expect(entry, isNull);
      } else {
        expect(entry?.label, 'Current');
        expect(entry?.currentRevision, '2');
        expect(entry?.currentKeyVersion, 3);
      }
    });
  }

  test(
    'Entry navigation uses the current exact Vault-scoped index head',
    () async {
      final index = _Index();
      when(() => index.waitForCurrent(any())).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Current credential',
          searchFields: [],
          revision: '42',
          currentKeyVersion: 3,
          state: MemberEntryState.active,
          iconReference: 'key',
        ),
      ]);
      when(() => index.entries('other-vault')).thenReturn(const []);
      final resolver = NotificationPresentationResolver(index: index);
      final entry = (await resolver.resolveEntry('vault', 'entry'))!;
      expect(entry.id, 'entry');
      expect(entry.vaultId, 'vault');
      expect(entry.label, 'Current credential');
      expect(entry.icon, 'key');
      expect(entry.currentRevision, '42');
      expect(entry.currentKeyVersion, 3);
      expect(await resolver.resolveEntry('other-vault', 'entry'), isNull);
      expect(await resolver.resolveEntry('vault', 'missing'), isNull);
    },
  );

  test(
    'Entry navigation refuses removed, corrupt, ambiguous and locked rows',
    () async {
      final index = _Index();
      when(() => index.waitForCurrent(any())).thenAnswer((_) async {});
      final resolver = NotificationPresentationResolver(index: index);
      for (final scenario in [
        (state: MemberEntryState.deleted, corrupt: false, count: 1),
        (state: MemberEntryState.active, corrupt: true, count: 1),
        (state: MemberEntryState.active, corrupt: false, count: 2),
        (state: MemberEntryState.active, corrupt: false, count: 0),
      ]) {
        when(() => index.entries('vault')).thenReturn(
          List.generate(
            scenario.count,
            (_) => MemberIndexEntry(
              entryId: 'entry',
              entryType: 1,
              memberLabel: 'Unavailable',
              searchFields: [],
              revision: '1',
              state: scenario.state,
              corrupt: scenario.corrupt,
            ),
          ),
        );
        expect(await resolver.resolveEntry('vault', 'entry'), isNull);
      }
    },
  );

  test('Entry navigation does not use stale rows after sync failure', () async {
    final index = _Index();
    when(
      () => index.waitForCurrent('vault'),
    ).thenAnswer((_) async => throw StateError('sync failed'));
    final resolver = NotificationPresentationResolver(index: index);
    await expectLater(
      resolver.resolveEntry('vault', 'entry'),
      throwsStateError,
    );
    verifyNever(() => index.entries(any()));
  });

  test('redaction removes decrypted reason and actor on lock', () {
    final resolver = NotificationPresentationResolver(index: _Index());
    final redacted = resolver.redact([
      _inbox(
        type: 'grant_approved',
        metadata: const {
          'vaultId': 'vault',
          'grantId': 'grant',
          'reason': 'Deploy release',
          'actorName': 'Alice',
        },
      ),
    ]);

    expect(redacted.single.metadata['reason'], isNull);
    expect(redacted.single.metadata['actorName'], isNull);
    expect(redacted.single.metadata['grantId'], isNull);
  });

  test('tap navigates only after authoritative inbox match', () async {
    final repository = _Repository();
    when(
      () => repository.list(cursor: any(named: 'cursor')),
    ).thenAnswer((_) async => NotificationPage(items: [_inbox()]));
    final cubit = PushNavigationCubit(
      analytics: AnalyticsService.instance,
      repository: repository,
    );
    await cubit.onNotificationTapped(_push());
    expect(cubit.state, '/inbox?focus=notification');

    when(() => repository.list(cursor: any(named: 'cursor'))).thenAnswer(
      (_) async => NotificationPage(items: [_inbox(subjectId: 'other')]),
    );
    cubit.consumed();
    await cubit.onNotificationTapped(_push());
    expect(cubit.state, isNull);
    await cubit.close();
  });
}
