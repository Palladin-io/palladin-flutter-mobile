import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/data/services/push_event_deduplicator.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/push_message.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/push_navigation_cubit.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';

class _Index extends Mock implements MemberIndexReader {}

class _Repository extends Mock implements NotificationCenterRepository {}

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
  Map<String, dynamic>? metadata,
}) => InboxNotification(
  id: id,
  subjectId: subjectId,
  type: 'credential_stale',
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
