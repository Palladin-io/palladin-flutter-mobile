import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/notification_preference.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';

void main() {
  late _FakeRepository repository;
  late NotificationCenterCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    cubit = NotificationCenterCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  test('load combines inbox page and summary', () async {
    await cubit.load();

    expect(cubit.state.status, NotificationCenterStatus.loaded);
    expect(cubit.state.items, hasLength(1));
    expect(cubit.state.unreadCount, 3);
    expect(cubit.state.pendingActionCount, 1);
  });

  test('markRead updates item and badge optimistically', () async {
    await cubit.load();
    await cubit.markRead('n-1');

    expect(cubit.state.items.single.isRead, isTrue);
    expect(cubit.state.unreadCount, 2);
    expect(repository.markedRead, ['n-1']);
  });

  test('markAllRead clears badge', () async {
    await cubit.load();
    await cubit.markAllRead();

    expect(cubit.state.unreadCount, 0);
    expect(cubit.state.items.every((item) => item.isRead), isTrue);
    expect(repository.didMarkAllRead, isTrue);
  });

  test('refresh is quiet and never flips to loading', () async {
    await cubit.load();
    final statuses = <NotificationCenterStatus>[];
    final sub = cubit.stream.listen((s) => statuses.add(s.status));
    await cubit.refresh();
    await sub.cancel();

    expect(statuses, isNot(contains(NotificationCenterStatus.loading)));
    expect(cubit.state.status, NotificationCenterStatus.loaded);
  });

  test('stale refresh does not reopen an action resolved locally', () async {
    await cubit.load();

    cubit.markResolvedLocally('n-1');
    await cubit.refreshSummary();
    expect(cubit.state.pendingActionCount, 0);

    await cubit.refresh();

    expect(
      cubit.state.items.single.actionState,
      NotificationActionState.resolved,
    );
    expect(cubit.state.pendingActionCount, 0);
  });

  test('paged refresh keeps suppression for an action outside page one',
      () async {
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    repository
      ..items = [_pendingNotification(id: 'n-2', grantId: 'g-2')]
      ..pendingActionCount = 2
      ..nextCursor = 'page-2';
    await cubit.refresh();
    await cubit.refreshSummary();

    expect(cubit.state.items.single.id, 'n-2');
    expect(cubit.state.pendingActionCount, 1);
  });

  test('loadMore retires suppression after a complete paged traversal',
      () async {
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    repository
      ..items = [_pendingNotification(id: 'n-2', grantId: 'g-2')]
      ..pendingActionCount = 2
      ..nextCursor = 'page-2';
    await cubit.refresh();

    repository
      ..items = const []
      ..nextCursor = null;
    await cubit.loadMore();

    repository.pendingActionCount = 1;
    await cubit.refreshSummary();

    expect(cubit.state.pendingActionCount, 1);
  });

  test('loadMore does not retire a guard without a fresh paged traversal',
      () async {
    repository.nextCursor = 'page-2';
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    repository
      ..items = const []
      ..nextCursor = null
      ..pendingActionCount = 1;
    await cubit.loadMore();
    await cubit.refreshSummary();

    expect(cubit.state.pendingActionCount, 0);
  });

  test('converged feed still suppresses its concurrently stale summary',
      () async {
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    repository
      ..items = const []
      ..pendingActionCount = 1;
    await cubit.refresh();

    expect(cubit.state.pendingActionCount, 0);

    repository
      ..items = [_pendingNotification(id: 'n-2', grantId: 'g-2')]
      ..pendingActionCount = 1;
    await cubit.refreshSummary();

    expect(cubit.state.pendingActionCount, 1);
  });

  test('overlapping stale summary keeps its request-start suppression',
      () async {
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    final staleSummary = Completer<NotificationSummary>();
    repository.summaryResponses.add(staleSummary.future);
    final staleRefresh = cubit.refreshSummary();

    repository
      ..items = const []
      ..pendingActionCount = 0;
    await cubit.refresh();

    staleSummary.complete(
      const NotificationSummary(unreadCount: 3, pendingActionCount: 1),
    );
    await staleRefresh;

    expect(cubit.state.pendingActionCount, 0);
  });

  test('request started before local resolution cannot restore its badge',
      () async {
    await cubit.load();

    final staleSummary = Completer<NotificationSummary>();
    repository.summaryResponses.add(staleSummary.future);
    final staleRefresh = cubit.refreshSummary();

    cubit.markResolvedLocally('n-1');
    repository
      ..items = const []
      ..pendingActionCount = 0;
    await cubit.refresh();

    staleSummary.complete(
      const NotificationSummary(unreadCount: 3, pendingActionCount: 1),
    );
    await staleRefresh;

    expect(cubit.state.pendingActionCount, 0);
  });

  test('server reconciliation restores counts for newer actions', () async {
    await cubit.load();
    cubit.markResolvedLocally('n-1');

    repository
      ..items = const []
      ..pendingActionCount = 0;
    await cubit.refresh();

    repository
      ..items = [_pendingNotification(id: 'n-2', grantId: 'g-2')]
      ..pendingActionCount = 1;
    await cubit.refresh();

    expect(cubit.state.items.single.id, 'n-2');
    expect(
      cubit.state.items.single.actionState,
      NotificationActionState.pending,
    );
    expect(cubit.state.pendingActionCount, 1);
  });

  test('markReadOnView drops the unread badge but keeps pendingActionCount',
      () async {
    await cubit.load();
    expect(cubit.state.pendingActionCount, 1);

    cubit.markReadOnView('n-1');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.items.single.isRead, isTrue);
    expect(cubit.state.unreadCount, 2);
    // The action / To-do counter is independent of read state.
    expect(cubit.state.pendingActionCount, 1);
    expect(repository.markedRead, ['n-1']);
  });

  test('markReadOnView is de-duped — never fires twice for the same id',
      () async {
    await cubit.load();
    cubit.markReadOnView('n-1');
    cubit.markReadOnView('n-1');
    await Future<void>.delayed(Duration.zero);

    expect(repository.markedRead, ['n-1']);
  });

  test('markReadOnView is a no-op for an already-read item', () async {
    await cubit.load();
    await cubit.markRead('n-1'); // already read
    repository.markedRead.clear();

    cubit.markReadOnView('n-1');
    await Future<void>.delayed(Duration.zero);

    expect(repository.markedRead, isEmpty);
  });

  test('mark-read is optimistic-only — never refetches the feed (no storm)',
      () async {
    await cubit.load();
    expect(repository.listCallCount, 1, reason: 'one fetch from load()');

    // Simulate many tile rebuilds firing mark-on-view for the same item
    // (the web storm scenario): scroll → remount → onSeen → markRead → …
    for (var i = 0; i < 50; i++) {
      cubit.markReadOnView('n-1');
    }
    await Future<void>.delayed(Duration.zero);

    // Exactly one PUT, and crucially NO extra feed fetch (would re-trigger
    // the loop on web). listCallCount stays at the single load() fetch.
    expect(repository.markedRead, ['n-1']);
    expect(repository.listCallCount, 1, reason: 'markRead must not refetch feed');
  });
}

class _FakeRepository implements NotificationCenterRepository {
  final List<String> markedRead = [];
  bool didMarkAllRead = false;
  List<InboxNotification> items = [_pendingNotification()];
  int pendingActionCount = 1;
  String? nextCursor;
  final List<Future<NotificationSummary>> summaryResponses = [];

  /// Counts feed list fetches — used to prove mark-read never refetches the
  /// feed (the web request-storm root cause).
  int listCallCount = 0;

  @override
  Future<NotificationPage> list({String? cursor}) async {
    listCallCount++;
    return NotificationPage(items: items, nextCursor: nextCursor);
  }

  @override
  Future<NotificationSummary> summary() async {
    if (summaryResponses.isNotEmpty) return summaryResponses.removeAt(0);
    return NotificationSummary(
      unreadCount: 3,
      pendingActionCount: pendingActionCount,
    );
  }

  @override
  Future<void> markRead(String id) async => markedRead.add(id);

  @override
  Future<void> markAllRead() async => didMarkAllRead = true;

  @override
  Future<List<NotificationPreference>> preferences() async => const [];

  @override
  Future<List<NotificationPreference>> updatePreference({
    required String type,
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  }) async => const [];
}

InboxNotification _pendingNotification({
  String id = 'n-1',
  String grantId = 'g-1',
}) => InboxNotification(
  id: id,
  type: 'grant_pending',
  category: NotificationCategory.actionRequired,
  titleKey: 'grant_pending',
  metadata: {'grantId': grantId, 'agentName': 'Acme-bot'},
  actionState: NotificationActionState.pending,
  occurredAt: DateTime(2026),
);
