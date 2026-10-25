import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';

class _Repository extends Mock implements NotificationCenterRepository {}

class _Grants extends Mock implements GrantsRepository {}

class _Index extends Mock implements MemberIndexReader {}

Grant _grant(String id) => Grant(
  id: id,
  vaultId: 'vault',
  agentId: 'agent',
  status: GrantStatus.active,
  scope: GrantScope.full,
  reason: 'Reason $id',
  createdAt: DateTime(2026),
);

InboxNotification _item(String id, {String? grantId}) => InboxNotification(
  id: id,
  type: 'grant_approved',
  category: NotificationCategory.update,
  titleKey: '',
  metadata: {
    'vaultId': 'vault',
    'grantId': grantId ?? id,
    'agentId': 'agent',
    'reason': 'FORGED',
    'actorName': 'FORGED',
  },
  actionState: NotificationActionState.none,
  occurredAt: DateTime(2026),
);

void main() {
  late _Repository repository;
  late _Grants grants;
  late NotificationCenterCubit cubit;
  setUp(() {
    repository = _Repository();
    grants = _Grants();
    when(() => repository.summary()).thenAnswer(
      (_) async =>
          const NotificationSummary(unreadCount: 2, pendingActionCount: 0),
    );
    cubit = NotificationCenterCubit(
      repository: repository,
      resolver: NotificationPresentationResolver(
        index: _Index(),
        grants: grants,
      ),
    );
    cubit.configureUnlockedResolution(
      activeAccountId: 'account',
      activeOrganizationId: 'org',
      activeVaults: [
        VaultEntity(
          id: 'vault',
          name: 'Vault',
          grantMode: GrantMode.granular,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          entryCount: 0,
          activeGrantCount: 0,
          memberCount: 1,
        ),
      ],
    );
  });
  tearDown(() => cubit.close());

  test('publishes safe feed and ready metadata before a slow grant', () async {
    final slow = Completer<Grant>();
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(items: [_item('slow'), _item('fast')]),
    );
    when(() => grants.getGrant('vault', 'slow')).thenAnswer((_) => slow.future);
    when(
      () => grants.getGrant('vault', 'fast'),
    ).thenAnswer((_) async => _grant('fast'));
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.status, NotificationCenterStatus.loaded);
    expect(cubit.state.items.map((item) => item.id), ['slow', 'fast']);
    expect(cubit.state.items.first.metadata.containsKey('reason'), false);
    expect(cubit.state.items.first.metadata.containsKey('actorName'), false);
    expect(cubit.state.items.last.metadata['reason'], 'Reason fast');
    slow.complete(_grant('slow'));
    await loading;
    expect(cubit.state.items.first.metadata['reason'], 'Reason slow');
  });

  test('shares duplicate grant requests within one page', () async {
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(
        items: [
          _item('first', grantId: 'same'),
          _item('second', grantId: 'same'),
        ],
      ),
    );
    when(
      () => grants.getGrant('vault', 'same'),
    ).thenAnswer((_) async => _grant('same'));
    await cubit.load();
    expect(cubit.state.items.map((item) => item.metadata['reason']), [
      'Reason same',
      'Reason same',
    ]);
    verify(() => grants.getGrant('vault', 'same')).called(1);
  });
  test(
    'bounds active grant hydration while keeping the whole feed visible',
    () async {
      final pending = List.generate(9, (_) => Completer<Grant>());
      var started = 0;
      when(() => repository.list()).thenAnswer(
        (_) async =>
            NotificationPage(items: [for (var i = 0; i < 9; i++) _item('$i')]),
      );
      when(() => grants.getGrant('vault', any())).thenAnswer((invocation) {
        started++;
        return pending[int.parse(invocation.positionalArguments[1] as String)]
            .future;
      });
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.items.length, 9);
      expect(started, inInclusiveRange(2, 4));
      for (var i = 0; i < 9; i++) {
        pending[i].complete(_grant('$i'));
      }
      await loading;
      expect(
        cubit.state.items.every((item) => item.metadata['reason'] != null),
        true,
      );
    },
  );

  for (final boundary in ['refresh', 'lock', 'reset']) {
    test('delayed grant metadata cannot overwrite $boundary', () async {
      final slow = Completer<Grant>();
      when(
        () => repository.list(),
      ).thenAnswer((_) async => NotificationPage(items: [_item('slow')]));
      when(
        () => grants.getGrant('vault', 'slow'),
      ).thenAnswer((_) => slow.future);
      final loading = cubit.load();
      await Future<void>.delayed(Duration.zero);
      switch (boundary) {
        case 'refresh':
          when(
            () => repository.list(),
          ).thenAnswer((_) async => const NotificationPage(items: []));
          await cubit.refresh();
        case 'lock':
          cubit.lock();
        case 'reset':
          cubit.reset();
      }
      final settled = cubit.state;
      slow.complete(_grant('slow'));
      await loading;
      expect(identical(cubit.state, settled), true);
      expect(
        cubit.state.items.every((item) => !item.metadata.containsKey('reason')),
        true,
      );
    });
  }

  test('metadata completion preserves a concurrent mark-read', () async {
    final slow = Completer<Grant>();
    when(
      () => repository.list(),
    ).thenAnswer((_) async => NotificationPage(items: [_item('slow')]));
    when(() => grants.getGrant('vault', 'slow')).thenAnswer((_) => slow.future);
    when(() => repository.markRead('slow')).thenAnswer((_) async {});
    final loading = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.markRead('slow');
    slow.complete(_grant('slow'));
    await loading;
    expect(cubit.state.items.single.isRead, true);
    expect(cubit.state.items.single.metadata['reason'], 'Reason slow');
    expect(cubit.state.unreadCount, 1);
  });
}
