import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_state.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_auth_lifecycle.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/auth-source-lifecycle');
  const claims = MemberSyncSessionAuthority(
    principalId: 'a',
    organizationId: 'o',
    organizationMembershipGeneration: '1',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );
  const authenticated = AuthAuthenticated(userId: 'a', isOnboarded: true);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<AuthState> states;
  late AutoFillSourceAccessService source;
  late List<String> events;
  late int epoch;
  Completer<void>? hold;
  bool fail = false;
  AutoFillAuthLifecycle? lifecycle;
  Future<void> begin() => source.begin(
    authority: claims,
    profileBinding: 'a' * 64,
    accountUnlock: const {},
  );
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    events = [];
    epoch = 0;
    hold = null;
    fail = false;
    states = StreamController<AuthState>.broadcast(sync: true);
    source = AutoFillSourceAccessService(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.method);
      switch (call.method) {
        case 'sourceSnapshot':
          return {'sourceEpoch': epoch, 'profileDigest': 'digest'};
        case 'revokeSourceSession':
        case 'revokeSource':
        case 'invalidateSource':
          await hold?.future;
          if (fail) throw PlatformException(code: 'SOURCE_UNAVAILABLE');
          return ++epoch;
        case 'beginSourceSession':
          return ++epoch;
        default:
          return null;
      }
    });
    await begin();
    events.clear();
  });
  tearDown(() async {
    await lifecycle?.dispose();
    lifecycle = null;
    await states.close();
    messenger.setMockMethodCallHandler(channel, null);
  });
  void attach(AuthState initial) {
    lifecycle = AutoFillAuthLifecycle(
      initialState: initial,
      states: states.stream,
      source: source,
      onTransition: () => events.add('local-reset'),
      onFailure: (_) => events.add('failure'),
    );
  }

  test(
    'cold authenticated, lock, unlock and loading preserve source session',
    () async {
      attach(authenticated);
      final ticket = await source.ticket();
      states.add(authenticated.copyWith(isVaultLocked: false));
      states.add(authenticated);
      states.add(const AuthLoading());
      states.add(authenticated);
      await flush();
      source.validateTicket(ticket);
      expect(events, isEmpty);
    },
  );

  for (final terminal in [
    const AuthUnauthenticated(),
    const AuthError('synthetic'),
  ]) {
    test(
      'terminal ${terminal.runtimeType} fences source before async cleanup',
      () async {
        attach(authenticated);
        final ticket = await source.ticket();
        states.add(const AuthLoading());
        states.add(terminal);
        expect(() => source.validateTicket(ticket), throwsStateError);
        expect(events, ['local-reset']);
        await flush();
        expect(events, contains('revokeSourceSession'));
        states.add(terminal);
        await flush();
        expect(events.where((e) => e == 'local-reset'), hasLength(1));
      },
    );
  }

  test(
    'biometric enrollment suppresses resume repair but not revocation',
    () async {
      attach(authenticated);
      final entered = Completer<void>();
      final release = Completer<void>();
      final enrollment = source.withBiometricMutation((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var repairs = 0;
      lifecycle!.runForegroundRepair(() => repairs++);
      expect(repairs, 0);
      final before = events.where((e) => e == 'revokeSourceSession').length;
      await source.invalidate(revokeAuthorization: true);
      expect(
        events.where((e) => e == 'revokeSourceSession').length,
        greaterThan(before),
      );
      release.complete();
      await enrollment;
      lifecycle!.runForegroundRepair(() => repairs++);
      expect(repairs, 1);
    },
  );

  test('initial signed-out state denies protected source', () async {
    source = AutoFillSourceAccessService(channel: channel);
    attach(const AuthUnauthenticated());
    expect(events, ['local-reset']);
    await flush();
    expect(events, contains('revokeSource'));
  });

  test('principal replacement holds bootstrap behind durable denial', () async {
    attach(authenticated);
    hold = Completer<void>();
    states.add(const AuthLoading());
    states.add(authenticated.copyWith(userId: 'b'));
    var completed = false;
    final next = begin().then((_) => completed = true);
    await flush();
    expect(completed, isFalse);
    expect(events, isNot(contains('beginSourceSession')));
    hold!.complete();
    await next;
    expect(
      events.indexOf('revokeSourceSession'),
      lessThan(events.indexOf('beginSourceSession')),
    );
  });

  test(
    'failed final denial remains a bootstrap barrier without retry loop',
    () async {
      attach(authenticated);
      fail = true;
      states.add(const AuthUnauthenticated());
      await flush();
      await expectLater(begin(), throwsA(isA<PlatformException>()));
      expect(events.where((e) => e == 'failure'), hasLength(1));
      expect(events.where((e) => e == 'revokeSourceSession'), hasLength(1));
      expect(events, isNot(contains('beginSourceSession')));
    },
  );
}
