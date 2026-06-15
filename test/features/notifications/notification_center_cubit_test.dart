import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/inbox_notification.dart';
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
    expect(cubit.state.openActionRequiredCount, 1);
  });

  test('markRead updates item and badge', () async {
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
        topic: 'access',
        title: 'Access requested',
        body: 'Review access.',
        data: const {'grantId': 'g-1'},
        isActionRequired: true,
        isSecurityCritical: false,
        isRead: false,
        isResolved: false,
        occurredAt: DateTime(2026),
      ),
    ],
  );

  @override
  Future<NotificationSummary> summary() async =>
      const NotificationSummary(unreadCount: 3, openActionRequiredCount: 1);

  @override
  Future<void> markRead(String id) async => markedRead.add(id);

  @override
  Future<void> markAllRead() async => didMarkAllRead = true;
}
