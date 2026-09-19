import 'privacy_fixture.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Remote remote;
  late AnalyticsService analytics;
  late ConsentCubit cubit;
  setUp(() async {
    remote = Remote();
    analytics = AnalyticsService();
    analytics.configure(
      projectKey: 'test-project',
      host: 'https://eu.i.posthog.com',
      released: true,
    );
    cubit = ConsentCubit(remote, analytics);
  });
  tearDown(() async {
    await cubit.close();
  });
  ConsentDecision decision(bool granted) =>
      cubit.decision(remote.current, granted, 'mobile_settings')!;

  test(
    'an existing account grant works on a fresh installation and after language change',
    () async {
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      await cubit.bind('account', 'en');
      expect(analytics.isInitialized, isTrue);
      await cubit.bind('account', 'pl');
      expect(analytics.isInitialized, isTrue);
      expect(remote.decisions, isEmpty);
    },
  );

  test(
    'cancelling a draft withdrawal restores only a freshly read saved choice',
    () async {
      remote.current = consent(
        status: 'granted',
        revision: 1,
        activationRevision: 1,
      );
      await cubit.bind('account', 'en');
      final resume = cubit.pauseAnalytics();
      await cubit.refresh();
      expect(analytics.isInitialized, isFalse);
      resume();
      await Future<void>.delayed(Duration.zero);
      expect(analytics.isInitialized, isTrue);
      expect(remote.decisions, isEmpty);
    },
  );

  test('stop fences a pending authoritative refresh', () async {
    await cubit.bind('account', 'en');
    await cubit.save(decision(true));
    remote.pendingRead = Completer<UserConsents>();
    final refreshing = cubit.refresh();
    cubit.pauseAnalytics();
    remote.pendingRead!.complete(UserConsents([remote.current], 60));
    await refreshing;
    expect(cubit.state.analyticsAuthorized, isFalse);
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
      remote.networkFails = false;
      remote.failReadAfterWrite = false;
      expect(await cubit.save(chosen), isTrue);
      expect(cubit.state.analyticsAuthorized, isTrue);
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
        cubit.pauseAnalytics();
        remote.networkFails = false;
        await cubit.refresh();
        expect(cubit.state.error, ConsentErrorKind.save);
        expect(remote.decisions, [failed]);
      },
    );
  }
  test('a late account read cannot authorize a replacement account', () async {
    remote.pendingRead = Completer<UserConsents>();
    remote.readStarted = Completer<void>();
    final oldRead = remote.pendingRead!;
    final binding = cubit.bind('old', 'en');
    await remote.readStarted!.future;
    remote.pendingRead = null;
    remote.readStarted = null;
    await cubit.bind('new', 'en');
    oldRead.complete(
      UserConsents([
        consent(status: 'granted', revision: 1, activationRevision: 1),
      ], 60),
    );
    await binding;
    expect(cubit.state.userId, 'new');
    expect(analytics.isInitialized, isFalse);
  });

  test(
    'a failed withdrawal immediately stops analytics and retains the identical retry',
    () async {
      await cubit.bind('account', 'en');
      await cubit.save(decision(true));
      remote.networkFails = true;
      final withdrawal = decision(false);
      expect(await cubit.save(withdrawal), isFalse);
      expect(analytics.isInitialized, isFalse);
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
    'withdrawal and regrant on another device automatically follow fresh account state',
    () async {
      await cubit.bind('account', 'en');
      await cubit.save(decision(true));
      remote.current = consent(status: 'withdrawn', revision: 2);
      await cubit.refresh();
      expect(analytics.isInitialized, isFalse);
      remote.current = consent(
        status: 'granted',
        revision: 3,
        activationRevision: 3,
      );
      await cubit.refresh();
      expect(analytics.isInitialized, isTrue);
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
      expect(analytics.isInitialized, isFalse);
    },
  );
}
