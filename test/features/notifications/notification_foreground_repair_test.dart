import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/domain/repositories/notification_center_repository.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/notifications/presentation/notification_foreground_repair.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _Auth extends Mock implements AuthBloc {}

class _Vaults extends Mock implements VaultListCubit {}

class _Repository extends Mock implements NotificationCenterRepository {}

void main() {
  late _Auth auth;
  late _Vaults vaults;
  late _Repository repository;
  late NotificationCenterCubit inbox;
  late NotificationForegroundRepair repair;
  late StreamController<AuthState> authEvents;
  late StreamController<VaultListState> vaultEvents;
  late AuthState authState;
  late VaultListState vaultState;
  late Future<MemberSyncSessionAuthority> Function() authority;
  final ready = AuthAuthenticated(
    userId: 'account',
    isOnboarded: true,
    isVaultLocked: false,
    privateKey: Uint8List(32),
  );
  const owner = MemberSyncSessionAuthority(
    principalId: 'account',
    organizationId: 'org',
    organizationMembershipGeneration: '1',
    offlinePolicy: 'disabled',
    offlinePolicyVersion: 1,
  );

  setUp(() {
    auth = _Auth();
    vaults = _Vaults();
    repository = _Repository();
    authState = ready;
    vaultState = const VaultListLoaded([]);
    authEvents = StreamController<AuthState>.broadcast(sync: true);
    vaultEvents = StreamController<VaultListState>.broadcast(sync: true);
    when(() => auth.state).thenAnswer((_) => authState);
    when(() => auth.stream).thenAnswer((_) => authEvents.stream);
    when(() => vaults.state).thenAnswer((_) => vaultState);
    when(() => vaults.stream).thenAnswer((_) => vaultEvents.stream);
    when(
      () => repository.list(),
    ).thenAnswer((_) async => const NotificationPage(items: []));
    when(() => repository.summary()).thenAnswer(
      (_) async =>
          const NotificationSummary(unreadCount: 0, pendingActionCount: 0),
    );
    inbox = NotificationCenterCubit(repository: repository);
    authority = () async => owner;
    repair = NotificationForegroundRepair(
      auth: auth,
      vaults: vaults,
      inbox: inbox,
      readAuthority: () => authority(),
    );
  });
  tearDown(() async {
    await repair.dispose();
    await inbox.close();
    await authEvents.close();
    await vaultEvents.close();
  });

  void repairTest(String name, void Function(FakeAsync) body) {
    test(
      name,
      () => fakeAsync((clock) {
        try {
          body(clock);
        } finally {
          unawaited(repair.dispose());
          clock.flushMicrotasks();
        }
      }),
    );
  }

  repairTest('foreground receipt repair is bounded and stops in background', (
    clock,
  ) {
    repair.start(foreground: true);
    clock.flushMicrotasks();
    verify(() => repository.list()).called(1);
    clock.elapse(const Duration(seconds: 29));
    verifyNever(() => repository.list());
    clock.elapse(const Duration(seconds: 1));
    verify(() => repository.list()).called(1);
    repair.setForeground(false);
    clock.elapse(const Duration(minutes: 2));
    verifyNever(() => repository.list());
    repair.setForeground(true);
    clock.flushMicrotasks();
    verify(() => repository.list()).called(1);
    unawaited(repair.dispose());
    clock.elapse(const Duration(minutes: 2));
    verifyNever(() => repository.list());
  });

  repairTest(
    'slow request is single-flight and late result after lock is discarded',
    (clock) {
      final response = Completer<NotificationPage>();
      when(() => repository.list()).thenAnswer((_) => response.future);
      repair.start(foreground: true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 2));
      verify(() => repository.list()).called(1);
      authState = ready.copyWith(isVaultLocked: true, clearKeys: true);
      authEvents.add(authState);
      final locked = inbox.state;
      response.complete(const NotificationPage(items: []));
      clock.flushMicrotasks();
      expect(identical(inbox.state, locked), true);
      clock.elapse(const Duration(minutes: 2));
      verifyNever(() => repository.list());
    },
  );

  for (final boundary in ['logout', 'vaults', 'background', 'dispose']) {
    repairTest('late authority cannot start repair after $boundary', (clock) {
      final pending = Completer<MemberSyncSessionAuthority>();
      authority = () => pending.future;
      repair.start(foreground: true);
      switch (boundary) {
        case 'logout':
          authState = const AuthUnauthenticated();
          authEvents.add(authState);
        case 'vaults':
          vaultState = const VaultListLocked();
          vaultEvents.add(vaultState);
        case 'background':
          repair.setForeground(false);
        case 'dispose':
          unawaited(repair.dispose());
      }
      pending.complete(owner);
      clock.flushMicrotasks();
      verifyNever(() => repository.list());
    });
  }

  repairTest('unavailable authority retries quietly at the next interval', (
    clock,
  ) {
    authority = () async => throw StateError('synthetic unavailable');
    repair.start(foreground: true);
    clock.flushMicrotasks();
    verifyNever(() => repository.list());
    authority = () async => owner;
    clock.elapse(const Duration(seconds: 30));
    verify(() => repository.list()).called(1);
  });

  repairTest('locked and not-ready accounts do not poll', (clock) {
    authState = ready.copyWith(emailVerified: false);
    repair.start(foreground: true);
    clock.elapse(const Duration(minutes: 2));
    verifyNever(() => repository.list());
    authState = ready;
    authEvents.add(authState);
    clock.flushMicrotasks();
    verify(() => repository.list()).called(1);
  });
}
