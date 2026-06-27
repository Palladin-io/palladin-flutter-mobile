import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/notification_preference.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_preferences_cubit.dart';

void main() {
  late _FakeRepository repository;
  late NotificationPreferencesCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    cubit = NotificationPreferencesCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  test('load fetches preferences', () async {
    await cubit.load();
    expect(cubit.state.status, NotificationPreferencesStatus.loaded);
    expect(cubit.state.items, hasLength(2));
  });

  test('toggle optimistically flips push and persists', () async {
    await cubit.load();
    await cubit.toggle(
      type: 'grant_approved',
      channel: NotificationChannel.push,
      value: true,
    );

    final pref = cubit.state.items.firstWhere((p) => p.type == 'grant_approved');
    expect(pref.pushEnabled, isTrue);
    expect(repository.lastUpdate?.type, 'grant_approved');
    expect(repository.lastUpdate?.pushEnabled, isTrue);
  });

  test('toggle sends the FULL channel triple, never a partial payload', () async {
    await cubit.load();
    // grant_approved starts inbox=true, signalR=true, push=false.
    await cubit.toggle(
      type: 'grant_approved',
      channel: NotificationChannel.push,
      value: true,
    );

    // All three channels must be present and non-null so the backend can't
    // zero the channels we did not toggle.
    expect(repository.lastUpdate?.inboxEnabled, isTrue);
    expect(repository.lastUpdate?.signalREnabled, isTrue);
    expect(repository.lastUpdate?.pushEnabled, isTrue);
  });

  test('disabling one channel keeps the others enabled in the payload', () async {
    await cubit.load();
    // Turn OFF realtime on grant_approved (inbox/push must stay as-is).
    await cubit.toggle(
      type: 'grant_approved',
      channel: NotificationChannel.realtime,
      value: false,
    );

    expect(repository.lastUpdate?.signalREnabled, isFalse);
    expect(repository.lastUpdate?.inboxEnabled, isTrue,
        reason: 'inbox not zeroed by a realtime toggle');
    expect(repository.lastUpdate?.pushEnabled, isFalse,
        reason: 'push preserved (was already false)');

    final pref = cubit.state.items.firstWhere((p) => p.type == 'grant_approved');
    expect(pref.inboxEnabled, isTrue);
    expect(pref.signalREnabled, isFalse);
  });

  test('mandatory inbox toggle is blocked client-side', () async {
    await cubit.load();
    await cubit.toggle(
      type: 'grant_pending',
      channel: NotificationChannel.inbox,
      value: false,
    );

    final pref = cubit.state.items.firstWhere((p) => p.type == 'grant_pending');
    expect(pref.inboxEnabled, isTrue, reason: 'mandatory inbox stays on');
    expect(repository.lastUpdate, isNull, reason: 'no network call made');
  });

  test('mandatory push toggle is allowed', () async {
    await cubit.load();
    await cubit.toggle(
      type: 'grant_pending',
      channel: NotificationChannel.push,
      value: false,
    );

    final pref = cubit.state.items.firstWhere((p) => p.type == 'grant_pending');
    expect(pref.pushEnabled, isFalse);
    expect(repository.lastUpdate?.type, 'grant_pending');
  });
}

class _FakeRepository implements NotificationCenterRepository {
  ({String type, bool? inboxEnabled, bool? signalREnabled, bool? pushEnabled})?
  lastUpdate;

  @override
  Future<List<NotificationPreference>> preferences() async => const [
    NotificationPreference(
      type: 'grant_pending',
      category: 'ActionRequired',
      inboxEnabled: true,
      signalREnabled: true,
      pushEnabled: true,
      mandatory: true,
    ),
    NotificationPreference(
      type: 'grant_approved',
      category: 'Update',
      inboxEnabled: true,
      signalREnabled: true,
      pushEnabled: false,
      mandatory: false,
    ),
  ];

  @override
  Future<List<NotificationPreference>> updatePreference({
    required String type,
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  }) async {
    lastUpdate = (
      type: type,
      inboxEnabled: inboxEnabled,
      signalREnabled: signalREnabled,
      pushEnabled: pushEnabled,
    );
    return const []; // echo nothing → keep optimistic state
  }

  // Unused in these tests.
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: []);

  @override
  Future<NotificationSummary> summary() async =>
      const NotificationSummary(unreadCount: 0, pendingActionCount: 0);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}
