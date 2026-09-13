import 'privacy_fixture.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/privacy/data/consent_activation_store.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Remote remote;
  late ConsentActivationStore store;
  late AnalyticsService analytics;
  late ConsentCubit cubit;
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('palladin-consent-test-');
    remote = Remote();
    store = ConsentActivationStore(cacheDirectory: () async => cache);
    analytics = AnalyticsService();
    analytics.configure(
      projectKey: 'test-project',
      host: 'https://eu.i.posthog.com',
      released: true,
    );
    cubit = ConsentCubit(remote, store, analytics);
  });
  tearDown(() async {
    await cubit.close();
    await cache.delete(recursive: true);
  });
  ConsentDecision decision(bool granted) =>
      cubit.decision(remote.current, granted, 'mobile_settings')!;

  for (final action in ['stop', 'withdraw']) {
    test('$action fences a cached activation read already in flight', () async {
      await cubit.close();
      final delayed = ControlledActivationStore()
        ..pendingRead = Completer<ConsentActivation?>()
        ..readStarted = Completer<void>();
      cubit = ConsentCubit(remote, delayed, analytics);
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      final binding = cubit.bind('account', 'en');
      await delayed.readStarted!.future;
      if (action == 'stop') {
        await cubit.stopHere();
      } else {
        remote.networkFails = true;
        expect(await cubit.save(decision(false)), isFalse);
        remote.networkFails = false;
      }
      delayed.pendingRead!.complete(const ConsentActivation('test-v1', 1));
      await binding;
      await cubit.refresh();
      expect(cubit.state.locallyActive, isFalse);
      expect(analytics.isInitialized, isFalse);
    });
  }

  for (final action in ['stop', 'withdraw']) {
    test(
      'failed $action deletion stays account-scoped across rebinds until explicit successful activation',
      () async {
        await cubit.close();
        final failing = ControlledActivationStore();
        cubit = ConsentCubit(remote, failing, analytics);
        await cubit.bind('account', 'en');
        await cubit.save(decision(true));
        await failing.write('other', const ConsentActivation('test-v1', 1));
        failing.failDelete = true;
        if (action == 'stop') {
          await cubit.stopHere();
        } else {
          remote.networkFails = true;
          expect(await cubit.save(decision(false)), isFalse);
          remote.networkFails = false;
        }
        expect(await failing.read('account'), isNotNull);
        await cubit.bind('account', 'pl');
        await cubit.refresh();
        expect(analytics.isInitialized, isFalse);
        await cubit.bind('other', 'en');
        expect(analytics.isInitialized, isTrue);
        await cubit.bind(null, 'en');
        await cubit.bind('account', 'en');
        cubit.setForeground(false);
        cubit.setForeground(true);
        await cubit.refresh();
        expect(cubit.state.locallyActive, isFalse);
        expect(analytics.isInitialized, isFalse);
        failing.failActivation = true;
        expect(await cubit.save(decision(true)), isFalse);
        await cubit.bind('account', 'pl');
        expect(analytics.isInitialized, isFalse);
        failing.failActivation = false;
        expect(await cubit.save(decision(true)), isTrue);
        expect(analytics.isInitialized, isTrue);
      },
    );
  }

  test('stop during activation persistence fences the late grant', () async {
    await cubit.close();
    final delayed = ControlledActivationStore()
      ..pendingActivation = Completer<void>()
      ..activationStarted = Completer<void>();
    cubit = ConsentCubit(remote, delayed, analytics);
    await cubit.bind('account', 'en');
    final saving = cubit.save(decision(true));
    await delayed.activationStarted!.future;
    await cubit.stopHere();
    delayed.pendingActivation!.complete();
    await saving;
    await cubit.bind('account', 'pl');
    expect(await delayed.read('account'), isNull);
    expect(cubit.state.locallyActive, isFalse);
    expect(analytics.isInitialized, isFalse);
  });

  test('stop fences a pending authoritative refresh', () async {
    await cubit.bind('account', 'en');
    await cubit.save(decision(true));
    remote.pendingRead = Completer<UserConsents>();
    final refreshing = cubit.refresh();
    await cubit.stopHere();
    remote.pendingRead!.complete(UserConsents([remote.current], 60));
    await refreshing;
    expect(cubit.state.locallyActive, isFalse);
    expect(analytics.isInitialized, isFalse);
  });

  test(
    'successful refresh recovers load error while preserving failed write retry',
    () async {
      await cubit.bind('account', 'en');
      remote.networkFails = true;
      final failed = decision(true);
      await cubit.save(failed);
      await cubit.refresh();
      expect(cubit.state.error, ConsentErrorKind.load);
      remote.networkFails = false;
      await cubit.refresh();
      expect(cubit.state.error, ConsentErrorKind.save);
      expect(cubit.state.failedDecision, same(failed));
      expect(await cubit.save(failed), isTrue);
      expect(cubit.state.error, isNull);
    },
  );

  for (final failRefresh in [false, true]) {
    test(
      '409 drops stale decision and requires reconfirmation after authoritative refresh (read failure: $failRefresh)',
      () async {
        await cubit.bind('account', 'en');
        final stale = decision(true);
        remote.current = consent(status: 'withdrawn', revision: 4);
        remote.writeStatus = 409;
        if (failRefresh) {
          remote.pendingRead = Completer<UserConsents>();
          remote.readStarted = Completer<void>();
        }
        final saving = cubit.save(stale);
        if (failRefresh) {
          await remote.readStarted!.future;
          remote.readStarted = null;
          remote.pendingRead!.completeError(StateError('network'));
        }
        expect(await saving, isFalse);
        expect(cubit.state.failedDecision, isNull);
        expect(cubit.state.requiresReconfirmation, isTrue);
        remote.pendingRead = null;
        await cubit.refresh();
        expect(cubit.state.error, isNull);
        expect(cubit.state.requiresReconfirmation, isTrue);
        expect(cubit.state.consents.single.revision, 4);
        expect(remote.decisions, [stale]);
        remote.writeStatus = null;
        final confirmed = cubit.decision(
          cubit.state.consents.single,
          true,
          'mobile_settings',
        )!;
        expect(confirmed.expectedRevision, 4);
        expect(confirmed.requestId, isNot(stale.requestId));
        expect(await cubit.save(confirmed), isTrue);
        expect(cubit.state.requiresReconfirmation, isFalse);
      },
    );
  }

  test(
    'transient refresh failure after a confirmed write retains recoverable retry',
    () async {
      await cubit.bind('account', 'en');
      remote.failReadAfterWrite = true;
      final chosen = decision(true);
      expect(await cubit.save(chosen), isFalse);
      expect(cubit.state.error, ConsentErrorKind.load);
      expect(cubit.state.failedDecision, same(chosen));
      await cubit.stopHere();
      remote.networkFails = false;
      remote.failReadAfterWrite = false;
      expect(await cubit.save(chosen), isTrue);
      expect(cubit.state.locallyActive, isTrue);
    },
  );

  for (final status in [400, 403, 408, 429, 500, 503]) {
    test(
      'HTTP $status retains identical decisions only for transient failures',
      () async {
        await cubit.bind('account', 'en');
        remote.writeStatus = status;
        final failed = decision(true);
        expect(await cubit.save(failed), isFalse);
        expect(
          cubit.state.failedDecision,
          status == 400 || status == 403 ? isNull : same(failed),
        );
        expect(cubit.state.error, ConsentErrorKind.save);
        await cubit.refresh();
        expect(cubit.state.error, ConsentErrorKind.save);
        remote.networkFails = true;
        await cubit.refresh();
        expect(cubit.state.error, ConsentErrorKind.load);
        await cubit.stopHere();
        remote.networkFails = false;
        await cubit.refresh();
        expect(cubit.state.error, ConsentErrorKind.save);
        expect(remote.decisions, [failed]);
      },
    );
  }
  test(
    'account consent alone does not activate a fresh installation',
    () async {
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      await cubit.bind('account', 'en');
      expect(cubit.state.locallyActive, isFalse);
      expect(analytics.isInitialized, isFalse);
      expect(await cubit.save(decision(true)), isTrue);
      expect(cubit.state.locallyActive, isTrue);
      expect(analytics.isInitialized, isTrue);
    },
  );
  test(
    'a late local read from the previous account cannot activate the new account',
    () async {
      await cubit.close();
      final delayed = _DelayedActivationStore();
      cubit = ConsentCubit(remote, delayed, analytics);
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      final oldBinding = cubit.bind('old', 'en');
      await delayed.started.future;
      await cubit.bind('new', 'en');
      delayed.oldRead.complete(const ConsentActivation('test-v1', 1));
      await oldBinding;
      await cubit.refresh();
      expect(cubit.state.userId, 'new');
      expect(cubit.state.locallyActive, isFalse);
      expect(analytics.isInitialized, isFalse);
    },
  );
  test(
    'a failed withdrawal immediately stops analytics and retains the identical retry',
    () async {
      await cubit.bind('account', 'en');
      await cubit.save(decision(true));
      remote.networkFails = true;
      final withdrawal = decision(false);
      expect(await cubit.save(withdrawal), isFalse);
      expect(analytics.isInitialized, isFalse);
      expect(await store.read('account'), isNull);
      expect(cubit.state.failedDecision, same(withdrawal));
      expect(cubit.state.saving, isFalse);
      await cubit.save(cubit.state.failedDecision!);
      expect(remote.decisions.last, same(withdrawal));
    },
  );
  test('a late grant after logout never activates either account', () async {
    await cubit.bind('old', 'en');
    remote.pending = Completer<UserConsent>();
    final saving = cubit.save(decision(true));
    await Future<void>.delayed(Duration.zero);
    await cubit.bind(null, 'en');
    remote.pending!.complete(
      consent(status: 'granted', revision: 1, activationRevision: 1),
    );
    expect(await saving, isFalse);
    expect(analytics.isInitialized, isFalse);
    expect(await store.read('old'), isNull);
  });
  test(
    'background and stale request completions cannot authorize analytics',
    () async {
      await cubit.bind('account', 'en');
      await cubit.save(decision(true));
      remote.pendingRead = Completer<UserConsents>();
      final refreshing = cubit.refresh();
      cubit.setForeground(false);
      remote.pendingRead!.complete(UserConsents([remote.current], 60));
      await refreshing;
      expect(analytics.isInitialized, isFalse);
      remote.pendingRead = null;
      cubit.setForeground(true);
      await cubit.refresh();
      expect(analytics.isInitialized, isTrue);
    },
  );
  test(
    'withdrawal and regrant on another device invalidates the previous local epoch',
    () async {
      await cubit.bind('account', 'en');
      await cubit.save(decision(true));
      remote.current = consent(
        status: 'granted',
        revision: 3,
        activationRevision: 3,
      );
      await cubit.refresh();
      expect(analytics.isInitialized, isFalse);
      expect(cubit.state.locallyActive, isFalse);
    },
  );
  test(
    'storage failure does not prevent sending the account withdrawal',
    () async {
      await cubit.close();
      cubit = ConsentCubit(remote, FailingStore(), analytics);
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      await cubit.bind('account', 'en');
      expect(await cubit.save(decision(false)), isTrue);
      expect(remote.decisions.single.granted, isFalse);
      expect(analytics.isInitialized, isFalse);
    },
  );
  test(
    'older idempotent grant retry does not activate a later server grant',
    () async {
      await cubit.bind('account', 'en');
      remote.pending = Completer<UserConsent>()
        ..complete(
          consent(status: 'granted', revision: 3, activationRevision: 3),
        );
      expect(await cubit.save(decision(true)), isTrue);
      expect(await store.read('account'), isNull);
      expect(analytics.isInitialized, isFalse);
    },
  );
}

class _DelayedActivationStore extends MemoryActivationStore {
  final started = Completer<void>();
  final oldRead = Completer<ConsentActivation?>();
  @override
  Future<ConsentActivation?> read(String userId) async {
    if (userId != 'old') return null;
    started.complete();
    return oldRead.future;
  }
}
