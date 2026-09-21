import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_reception.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_reception_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_account_continuation.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_receiver_host.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_receiver_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Remote extends Mock implements EntryShareRecipientDatasource {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/entry-sharing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const id = '00112233-4455-4677-8899-aabbccddeeff';
  final initial = DateTime.utc(2026, 9, 21);
  final fragment = '#v=1&key=${'A' * 42}E&access=${'A' * 42}I';
  late _Auth auth;
  late StreamController<AuthState> authEvents;
  late EntryShareIngress ingress;
  late EntryShareCryptoService crypto;
  late List<_Remote> remotes;
  late DateTime now;
  late Duration elapsed;
  late int nativeGeneration;
  late String recipientMode;
  Map<String, Object?>? nativeReply;
  late Future<EntryShareRecipientOwner?> Function(String?) ownerReader;
  late GlobalKey<NavigatorState> navigator;

  setUpAll(() {
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      const EntryShareRecipientSession(
        sessionId: '',
        sessionToken: '',
        expiresAt: '',
        recipientMode: '',
        protection: '',
      ),
    );
  });
  setUp(() {
    auth = _Auth();
    authEvents = StreamController<AuthState>();
    whenListen(
      auth,
      authEvents.stream,
      initialState: const AuthUnauthenticated(),
    );
    crypto = EntryShareCryptoService(
      sodiumLoader: () async =>
          throw StateError('No crypto operation expected'),
    );
    remotes = [];
    now = initial;
    elapsed = Duration.zero;
    nativeGeneration = 0;
    recipientMode = 'anyoneWithLink';
    nativeReply = null;
    navigator = GlobalKey<NavigatorState>();
    ownerReader = (principal) async => (
      principalId: principal,
      organizationId: principal == null ? null : 'org-a',
      authorizationGeneration: principal == null ? null : '1',
      keyGeneration: 0,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      final reply = nativeReply;
      nativeReply = null;
      return reply;
    });
    ingress = EntryShareIngress(
      links: EntryShareLinkService(
        EnvConfig.staging(sharingWebOrigin: 'https://stage.palladin.io'),
      ),
      now: () => now,
      elapsed: () => elapsed,
    );
  });
  tearDown(() async {
    ingress.dispose();
    await authEvents.close();
    await auth.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  _Remote remoteFactory() {
    final remote = _Remote();
    when(
      () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer(
      (_) async => EntryShareRecipientSession(
        sessionId: 'synthetic-session',
        sessionToken: 'synthetic-token',
        expiresAt: initial.add(const Duration(minutes: 10)).toIso8601String(),
        recipientMode: recipientMode,
        protection: 'none',
      ),
    );
    when(
      () => remote.requestOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        language: any(named: 'language'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => Duration.zero);
    remotes.add(remote);
    return remote;
  }

  Future<void> link(WidgetTester tester, {String? url}) async {
    nativeReply = {
      'generation': ++nativeGeneration,
      'url': url ?? 'https://stage.palladin.io/share/$id$fragment',
      'receivedAtUnixMs': initial.millisecondsSinceEpoch,
      'ageMilliseconds': elapsed.inMilliseconds,
    };
    messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('pending', nativeGeneration)),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester, {
    VoidCallback? onClose,
    EntryShareAccountContinuation? accountContinuation,
    ValueChanged<String>? onAccountRoute,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    unawaited(ingress.start());
    await tester.pump();
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EntryShareReceiverHost(
            ingress: ingress,
            crypto: crypto,
            remoteFactory: remoteFactory,
            ownerReader: (id) => ownerReader(id),
            onClose: onClose,
            accountContinuation: accountContinuation,
            onAccountRoute: onAccountRoute,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  EntryShareReceptionCubit receiver(WidgetTester tester) => tester
      .widget<EntryShareReceiverPage>(find.byType(EntryShareReceiverPage))
      .cubit;
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  for (final register in [false, true]) {
    testWidgets(
      'mounted account CTA returns the same reception: register=$register',
      (tester) async {
        final continuation = EntryShareAccountContinuation(
          auth: auth,
          ingress: ingress,
          ownerReader: (id) => ownerReader(id),
        );
        addTearDown(continuation.dispose);
        String? accountRoute;
        await mount(
          tester,
          accountContinuation: continuation,
          onAccountRoute: (route) {
            accountRoute = route;
            continuation.guardRoute(Uri.parse(route));
            unawaited(
              navigator.currentState!.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Account flow')),
                ),
              ),
            );
          },
        );
        await link(tester);
        await tester.tap(find.text('Open sharing'));
        await tester.pumpAndSettle();
        final original = receiver(tester);
        final lifetime = original.lifetime;
        final version = ingress.version;
        final cta = find.text(
          register
              ? 'Create an account to save a copy'
              : 'Sign in to save a copy',
        );
        await tester.ensureVisible(cta);
        await tester.tap(cta);
        await tester.pumpAndSettle();
        expect(accountRoute, register ? '/register' : '/login');
        expect(find.text('Account flow'), findsOneWidget);
        expect(original.isClosed, true);
        expect(continuation.active, true);
        expect(ingress.version, version);
        verifyNever(() => remotes.single.close());
        authEvents.add(
          AuthAuthenticated(
            userId: 'recipient',
            isOnboarded: true,
            isVaultLocked: false,
            privateKey: Uint8List(32),
          ),
        );
        await tester.pumpAndSettle();
        expect(continuation.ready, true);
        continuation.guardRoute(Uri.parse('/share'));
        unawaited(
          navigator.currentState!.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => EntryShareReceiverHost(
                ingress: ingress,
                crypto: crypto,
                remoteFactory: remoteFactory,
                ownerReader: (id) => ownerReader(id),
                accountContinuation: continuation,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          receiver(tester).state.phase,
          EntryShareReceptionPhase.verification,
        );
        expect(receiver(tester).lifetime, same(lifetime));
        expect(continuation.active, false);
        expect(remotes.length, 1);
        verify(
          () => remotes.single.open(
            id,
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        await unmount(tester);
        verify(() => remotes.single.close()).called(1);
      },
    );
  }

  testWidgets(
    'native link mounts guest receiver but never opens a remote session automatically',
    (tester) async {
      await mount(tester);
      await link(tester);
      expect(find.text('Open sharing'), findsOneWidget);
      verifyZeroInteractions(remotes.single);
      await tester.tap(find.text('Open sharing'));
      await tester.pumpAndSettle();
      verify(
        () => remotes.single.open(
          id,
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(
        receiver(tester).state.phase,
        EntryShareReceptionPhase.verification,
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'auth restoration waits before claiming the one-shot capability',
    (tester) async {
      when(() => auth.state).thenReturn(const AuthInitial());
      await mount(tester);
      await link(tester);
      expect(find.byType(EntryShareReceiverPage), findsNothing);
      expect(ingress.hasPending, true);
      authEvents.add(const AuthUnauthenticated());
      await tester.pump();
      await tester.pump();
      expect(find.text('Open sharing'), findsOneWidget);
      expect(ingress.hasPending, false);
      await unmount(tester);
    },
  );

  testWidgets(
    'close disposes locally before navigation without ending the link',
    (tester) async {
      EntryShareReceptionCubit? current;
      var closed = false;
      await mount(
        tester,
        onClose: () {
          closed = true;
          expect(current!.isClosed, true);
          expect(current.state.phase, EntryShareReceptionPhase.unavailable);
          expect(ingress.hasPending, false);
        },
      );
      await link(tester);
      current = receiver(tester);
      await tester.tap(find.text('Open sharing'));
      await tester.pumpAndSettle();
      clearInteractions(remotes.single);
      await tester.tap(find.byTooltip('Close sharing'));
      await tester.pump();
      expect(closed, true);
      verify(() => remotes.single.close()).called(greaterThanOrEqualTo(1));
      verifyNoMoreInteractions(remotes.single);
      await unmount(tester);
    },
  );

  testWidgets(
    'close while resolving ownership cannot revive the pending link',
    (tester) async {
      final pending = Completer<EntryShareRecipientOwner?>();
      ownerReader = (_) => pending.future;
      var closed = false;
      await mount(tester, onClose: () => closed = true);
      await link(tester);
      expect(ingress.hasPending, true);
      await tester.tap(find.byTooltip('Close sharing'));
      expect(closed, true);
      expect(ingress.hasPending, false);
      pending.complete((
        principalId: null,
        organizationId: null,
        authorizationGeneration: null,
        keyGeneration: 0,
      ));
      await tester.pump();
      await tester.pump();
      expect(remotes, isEmpty);
      expect(find.byType(EntryShareReceiverPage), findsNothing);
      await unmount(tester);
    },
  );

  for (final failure in [false, true]) {
    testWidgets(
      'superseded owner lookup cannot retire a fresh receiver (failure=$failure)',
      (tester) async {
        final pending = Completer<EntryShareRecipientOwner?>();
        final readCurrentOwner = ownerReader;
        ownerReader = (_) => pending.future;
        await mount(tester);
        await link(tester);
        ownerReader = readCurrentOwner;
        await link(tester);
        final current = receiver(tester);
        if (failure) {
          pending.completeError(StateError('synthetic'));
        } else {
          pending.complete(await readCurrentOwner(null));
        }
        await tester.pump();
        await tester.pump();
        expect(receiver(tester), same(current));
        expect(current.isClosed, false);
        expect(find.text('Open sharing'), findsOneWidget);
        expect(remotes.length, 1);
        verifyZeroInteractions(remotes.single);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'locked unverified account can receive without opening its vault',
    (tester) async {
      when(() => auth.state).thenReturn(
        const AuthAuthenticated(
          userId: 'user-a',
          isOnboarded: false,
          emailVerified: false,
        ),
      );
      await mount(tester);
      await link(tester);
      expect(find.text('Open sharing'), findsOneWidget);
      verifyZeroInteractions(remotes.single);
      await unmount(tester);
    },
  );

  for (final failure in [false, true]) {
    testWidgets(
      'account change fences a pending owner read (failure=$failure)',
      (tester) async {
        final pending = Completer<EntryShareRecipientOwner?>();
        ownerReader = (_) => pending.future;
        await mount(tester);
        await link(tester);
        authEvents.add(
          const AuthAuthenticated(userId: 'user-a', isOnboarded: true),
        );
        await tester.pump();
        if (failure) {
          pending.completeError(StateError('synthetic'));
        } else {
          pending.complete((
            principalId: null,
            organizationId: null,
            authorizationGeneration: null,
            keyGeneration: 0,
          ));
        }
        await tester.pump();
        await tester.pump();
        expect(remotes, isEmpty);
        expect(find.byType(EntryShareReceiverPage), findsNothing);
        expect(ingress.hasPending, false);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'new same-ID link immediately retires the old Cubit and remounts a fresh welcome',
    (tester) async {
      await mount(tester);
      await link(tester);
      final old = receiver(tester);
      await tester.tap(find.text('Open sharing'));
      await tester.pumpAndSettle();
      await link(tester);
      expect(old.isClosed, true);
      expect(old.state.phase, EntryShareReceptionPhase.unavailable);
      expect(receiver(tester), isNot(same(old)));
      expect(find.text('Open sharing'), findsOneWidget);
      verify(() => remotes.first.close()).called(greaterThanOrEqualTo(1));
      verifyZeroInteractions(remotes.last);
      await unmount(tester);
    },
  );

  testWidgets(
    'malformed replacement retires the old receiver with no fallback',
    (tester) async {
      await mount(tester);
      await link(tester);
      final old = receiver(tester);
      await link(tester, url: 'https://evil.example.test/share/$id$fragment');
      expect(old.isClosed, true);
      expect(find.byType(EntryShareReceiverPage), findsNothing);
      expect(find.text('Open sharing'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'key replacement retires received context even for the same user',
    (tester) async {
      when(() => auth.state).thenReturn(
        AuthAuthenticated(
          userId: 'user-a',
          isOnboarded: true,
          isVaultLocked: false,
          privateKey: Uint8List(32),
        ),
      );
      await mount(tester);
      await link(tester);
      final old = receiver(tester);
      authEvents.add(
        AuthAuthenticated(
          userId: 'user-a',
          isOnboarded: true,
          isVaultLocked: false,
          privateKey: Uint8List(32),
        ),
      );
      await tester.pump();
      expect(old.isClosed, true);
      await tester.pump();
      expect(find.byType(EntryShareReceiverPage), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets('authority mismatch never creates a remote transport', (
    tester,
  ) async {
    ownerReader = (_) async => (
      principalId: 'foreign',
      organizationId: null,
      authorizationGeneration: null,
      keyGeneration: 0,
    );
    await mount(tester);
    await link(tester);
    expect(remotes, isEmpty);
    expect(ingress.hasPending, false);
    expect(
      find.text(
        'This sharing link is unavailable. Reopen the original link if it is still valid.',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets(
    'background during owner lookup waits in RAM and rejects its late result',
    (tester) async {
      final pending = Completer<EntryShareRecipientOwner?>();
      final guest = (
        principalId: null,
        organizationId: null,
        authorizationGeneration: null,
        keyGeneration: 0,
      );
      ownerReader = (_) => pending.future;
      await mount(tester);
      await link(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(guest);
      await tester.pump();
      expect(remotes, isEmpty);
      expect(ingress.hasPending, true);
      ownerReader = (_) async => guest;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Open sharing'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('waiting for auth never restarts the original ingress deadline', (
    tester,
  ) async {
    when(() => auth.state).thenReturn(const AuthInitial());
    await mount(tester);
    await link(tester);
    elapsed = const Duration(minutes: 14);
    authEvents.add(const AuthUnauthenticated());
    await tester.pump();
    await tester.pump();
    final current = receiver(tester);
    elapsed = const Duration(minutes: 15);
    expect(await current.revalidate(), false);
    expect(current.state.phase, EntryShareReceptionPhase.unavailable);
    await unmount(tester);
  });

  testWidgets('new link closes the previous termination confirmation', (
    tester,
  ) async {
    await mount(tester);
    await link(tester);
    await tester.tap(find.text('Open sharing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End sharing'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await link(tester);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Open sharing'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'host preserves the same pre-delivery OTP session through email app return',
    (tester) async {
      recipientMode = 'namedRecipient';
      await mount(tester);
      await link(tester);
      await tester.tap(find.text('Open sharing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      final original = receiver(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(original.state.suspended, true);
      expect(original.isClosed, false);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(receiver(tester), same(original));
      expect(original.state.suspended, false);
      expect(find.text('Verify email code'), findsOneWidget);
      expect(remotes.length, 1);
      await unmount(tester);
    },
  );

  testWidgets('terminal auth error does not leave an unclaimed link spinning', (
    tester,
  ) async {
    when(() => auth.state).thenReturn(const AuthInitial());
    await mount(tester);
    await link(tester);
    authEvents.add(AuthError(StateError('synthetic')));
    await tester.pump();
    await tester.pump();
    expect(ingress.hasPending, false);
    expect(
      find.text(
        'This sharing link is unavailable. Reopen the original link if it is still valid.',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('covering route drops ownership and returning never reopens it', (
    tester,
  ) async {
    await mount(tester);
    await link(tester);
    final old = receiver(tester);
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(old.isClosed, true);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(EntryShareReceiverPage), findsNothing);
    await unmount(tester);
  });
}
