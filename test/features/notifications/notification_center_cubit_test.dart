import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/notification_preference.dart';
import 'package:mobile_claw_vault/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_claw_vault/features/notifications/presentation/cubit/notification_center_cubit.dart';

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
}

class _FakeRepository implements NotificationCenterRepository {
  final List<String> markedRead = [];
  bool didMarkAllRead = false;

  @override
  Future<NotificationPage> list({String? cursor}) async => NotificationPage(
    items: [
      InboxNotification(
        id: 'n-1',
        type: 'grant_pending',
        category: NotificationCategory.actionRequired,
        titleKey: 'grant_pending',
        metadata: const {'grantId': 'g-1', 'agentName': 'Acme-bot'},
        actionState: NotificationActionState.pending,
        occurredAt: DateTime(2026),
      ),
    ],
  );

  @override
  Future<NotificationSummary> summary() async =>
      const NotificationSummary(unreadCount: 3, pendingActionCount: 1);

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
