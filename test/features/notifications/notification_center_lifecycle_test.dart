import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/exceptions/notification_center_exceptions.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';

class _Repository extends Mock implements NotificationCenterRepository {}

class _Index extends Mock implements MemberIndexReader {}

final _receipt = InboxNotification(
  id: 'old-receipt',
  type: 'entry_share_received',
  category: NotificationCategory.update,
  titleKey: '',
  metadata: const {},
  actionState: NotificationActionState.none,
  occurredAt: DateTime(2026),
);
const _summary = NotificationSummary(unreadCount: 1, pendingActionCount: 0);

void main() {
  late _Repository repository;
  late NotificationCenterCubit cubit;
  setUp(() {
    repository = _Repository();
    when(() => repository.summary()).thenAnswer((_) async => _summary);
    when(() => repository.list()).thenAnswer(
      (_) async => NotificationPage(items: [_receipt], nextCursor: 'next'),
    );
    cubit = NotificationCenterCubit(repository: repository);
  });
  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  for (final operation in ['load', 'refresh', 'summary', 'more']) {
    for (final boundary in ['reset', 'lock', 'account', 'close']) {
      test('$operation cannot publish after $boundary', () async {
        cubit.configureUnlockedResolution(
          activeAccountId: 'old',
          activeOrganizationId: 'org',
          activeVaults: const [],
        );
        await cubit.load();
        final page = Completer<NotificationPage>();
        final summary = Completer<NotificationSummary>();
        when(() => repository.list()).thenAnswer((_) => page.future);
        when(
          () => repository.list(cursor: 'next'),
        ).thenAnswer((_) => page.future);
        when(() => repository.summary()).thenAnswer((_) => summary.future);
        final pending = switch (operation) {
          'load' => cubit.load(),
          'refresh' => cubit.refresh(),
          'summary' => cubit.refreshSummary(),
          _ => cubit.loadMore(),
        };
        switch (boundary) {
          case 'reset':
            cubit.reset();
          case 'lock':
            cubit.lock();
          case 'account':
            cubit.configureUnlockedResolution(
              activeAccountId: 'new',
              activeOrganizationId: 'org',
              activeVaults: const [],
            );
          case 'close':
            await cubit.close();
        }
        final settled = cubit.state;
        page.complete(NotificationPage(items: [_receipt]));
        summary.complete(
          const NotificationSummary(unreadCount: 99, pendingActionCount: 99),
        );
        await pending;
        expect(identical(cubit.state, settled), true);
        if (boundary == 'reset' || boundary == 'account') {
          expect(cubit.state.items, isEmpty);
        }
      });
    }
  }

  for (final all in [false, true]) {
    test(
      'failed mark read all=$all cannot restore a logged-out feed',
      () async {
        await cubit.load();
        final request = Completer<void>();
        when(
          () => repository.markRead('old-receipt'),
        ).thenAnswer((_) => request.future);
        when(() => repository.markAllRead()).thenAnswer((_) => request.future);
        final pending = all
            ? cubit.markAllRead()
            : cubit.markRead('old-receipt');
        cubit.reset();
        request.completeError(
          const NotificationCenterException(
            NotificationCenterErrorKind.unknown,
          ),
        );
        await pending;
        expect(cubit.state.items, isEmpty);
        expect(cubit.state.unreadCount, 0);
        expect(cubit.state.isMarkingAllRead, false);
      },
    );
  }

  test('older feed cannot replace a newer refresh', () async {
    final old = Completer<NotificationPage>();
    when(() => repository.list()).thenAnswer((_) => old.future);
    final pending = cubit.load();
    when(
      () => repository.list(),
    ).thenAnswer((_) async => const NotificationPage(items: []));
    await cubit.refresh();
    old.complete(NotificationPage(items: [_receipt]));
    await pending;
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.status, NotificationCenterStatus.loaded);
  });

  for (final boundary in ['lock', 'reset', 'account']) {
    test('local labels completing after $boundary never reach Inbox', () async {
      await cubit.close();
      final index = _Index();
      final resolving = Completer<void>();
      final entered = Completer<void>();
      when(() => index.waitForCurrent('vault')).thenAnswer((_) {
        entered.complete();
        return resolving.future;
      });
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Private local label',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      cubit = NotificationCenterCubit(
        repository: repository,
        resolver: NotificationPresentationResolver(index: index),
      );
      cubit.configureUnlockedResolution(
        activeAccountId: 'old',
        activeOrganizationId: 'org',
        activeVaults: [
          VaultEntity(
            id: 'vault',
            name: 'Private vault',
            grantMode: GrantMode.granular,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            entryCount: 1,
            activeGrantCount: 0,
            memberCount: 1,
          ),
        ],
      );
      when(() => repository.list()).thenAnswer(
        (_) async => NotificationPage(
          items: [
            InboxNotification(
              id: 'receipt',
              type: 'entry_share_received',
              category: NotificationCategory.update,
              titleKey: '',
              actionState: NotificationActionState.none,
              occurredAt: DateTime(2026),
              metadata: const {'vaultId': 'vault', 'entryId': 'entry'},
            ),
          ],
        ),
      );
      final pending = cubit.load();
      await entered.future;
      switch (boundary) {
        case 'lock':
          cubit.lock();
        case 'reset':
          cubit.reset();
        case 'account':
          cubit.configureUnlockedResolution(
            activeAccountId: 'new',
            activeOrganizationId: 'new-org',
            activeVaults: const [],
          );
      }
      final settled = cubit.state;
      resolving.complete();
      await pending;
      expect(identical(cubit.state, settled), true);
      expect(cubit.state.items, isEmpty);
    });
  }

  test('late typed load failure cannot replace a reset state', () async {
    final response = Completer<NotificationPage>();
    when(() => repository.list()).thenAnswer((_) => response.future);
    final pending = cubit.load();
    cubit.reset();
    response.completeError(
      const NotificationCenterException(
        NotificationCenterErrorKind.networkError,
      ),
    );
    await pending;
    expect(cubit.state.status, NotificationCenterStatus.initial);
    expect(cubit.state.error, isNull);
  });

  test('old pagination cannot append after a newer first page', () async {
    await cubit.load();
    final page = Completer<NotificationPage>();
    when(() => repository.list(cursor: 'next')).thenAnswer((_) => page.future);
    final pending = cubit.loadMore();
    when(
      () => repository.list(),
    ).thenAnswer((_) async => const NotificationPage(items: []));
    await cubit.refresh();
    page.complete(NotificationPage(items: [_receipt]));
    await pending;
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.isLoadingMore, false);
  });

  test('mark-read rollback cannot discard a newer feed', () async {
    await cubit.load();
    final request = Completer<void>();
    when(
      () => repository.markRead('old-receipt'),
    ).thenAnswer((_) => request.future);
    final pending = cubit.markRead('old-receipt');
    when(
      () => repository.list(),
    ).thenAnswer((_) async => const NotificationPage(items: []));
    await cubit.refresh();
    request.completeError(
      const NotificationCenterException(
        NotificationCenterErrorKind.networkError,
      ),
    );
    await pending;
    expect(cubit.state.items, isEmpty);
  });
}
