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
