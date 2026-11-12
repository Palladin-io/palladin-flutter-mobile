import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_request_host.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _Auth extends Mock implements AuthBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/request-host');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await getIt.reset();
  });
  for (final lockDuringRedirect in [false, true]) {
    testWidgets(
      'router unlock redirect: lockDuringRedirect=$lockDuringRedirect preserves cancellation boundaries',
      (tester) async {
        final states = StreamController<AuthState>.broadcast();
        final auth = _Auth();
        AuthState authState = const AuthAuthenticated(
          userId: 'p',
          isOnboarded: true,
        );
        when(() => auth.state).thenAnswer((_) => authState);
        when(() => auth.stream).thenAnswer((_) => states.stream);
        final refresh = ChangeNotifier();
        final redirect = Completer<String?>();
        final canceled = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') {
            canceled.add((call.arguments as Map)['id'] as String);
          }
          return switch (call.method) {
            'pending' => {
              'id': 'request',
              'mode': 'WEB',
              'verifiedHosts': ['example.com'],
              'usernameOnly': false,
              'remainingMs': 30000,
            },
            'beginSourceSession' => 1,
            'bind' => 'binding',
            'authorizeUnlockedSession' => 'authorization',
            _ => null,
          };
        });
        const claims = MemberSyncSessionAuthority(
          principalId: 'p',
          organizationId: 'o',
          organizationMembershipGeneration: '1',
          offlinePolicy: '24h',
          offlinePolicyVersion: 1,
        );
        final source = AutoFillSourceAccessService(channel: channel);
        await source.begin(
          authority: claims,
          profileBinding: 'a' * 64,
          accountUnlock: const {},
        );
        final requests = AutoFillRequestController(
          source: source,
          channel: channel,
          authority: MemberSyncSessionAuthorityProvider.independent(
            readClaims: () async => claims,
            sessionRevision: () => 0,
          ),
        );
        getIt.registerSingleton<AutoFillSourceAccessService>(source);
        getIt.registerSingleton<AutoFillRequestController>(requests);
        final navigator = GlobalKey<NavigatorState>();
        final shellNavigator = GlobalKey<NavigatorState>();
        final router = GoRouter(
          navigatorKey: navigator,
          initialLocation: '/unlock',
          refreshListenable: refresh,
          redirect: (_, state) {
            if (state.uri.path == '/unlock' &&
                !(authState as AuthAuthenticated).isVaultLocked) {
              return redirect.future;
            }
            return null;
          },
          routes: [
            GoRoute(
              path: '/unlock',
              builder: (_, _) => const Scaffold(body: Text('Unlock')),
            ),
            ShellRoute(
              navigatorKey: shellNavigator,
              builder: (_, _, child) => Column(
                children: [
                  Expanded(child: child),
                  const Text('Palladin navigation'),
                ],
              ),
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: Text('Home')),
                ),
                GoRoute(
                  path: '/entries',
                  builder: (_, _) => const Scaffold(body: Text('Entries tab')),
                ),
              ],
            ),
          ],
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, child) => AutoFillRequestHost(
                router: router,
                navigatorKey: navigator,
                shellNavigatorKey: shellNavigator,
                prepare: () => throw StateError('unused'),
                requestPageBuilder: (_) => const Scaffold(body: Text('Picker')),
                child: child!,
              ),
            ),
          ),
        );
        await requests.poll();
        await tester.pumpAndSettle();
        expect(find.text('Unlock'), findsOneWidget);
        authState = AuthAuthenticated(
          userId: 'p',
          isOnboarded: true,
          isVaultLocked: false,
          privateKey: Uint8List(32),
        );
        states.add(authState);
        refresh.notifyListeners();
        await tester.pumpAndSettle();
        // On baseline the pageless picker attaches to /unlock, then is removed
        // when the actual redirect completes, canceling the native request.
        expect(find.text('Picker'), findsNothing);
        if (lockDuringRedirect) {
          authState = const AuthAuthenticated(userId: 'p', isOnboarded: true);
          states.add(authState);
          await tester.pumpAndSettle();
        }
        redirect.complete('/');
        await tester.pumpAndSettle();
        if (lockDuringRedirect) {
          expect(find.text('Picker'), findsNothing);
        } else {
          expect(requests.request, isNotNull);
          expect(canceled, isEmpty);
          expect(find.text('Picker'), findsOneWidget);
          expect(find.text('Palladin navigation'), findsOneWidget);
          expect(shellNavigator.currentState!.canPop(), isTrue);
          router.go('/entries');
          await tester.pumpAndSettle();
        }
        expect(canceled, ['request']);
        expect(requests.request, isNull);
        await tester.pumpWidget(const SizedBox());
        requests.dispose();
        router.dispose();
        refresh.dispose();
        await states.close();
      },
    );
  }
  testWidgets(
    'incoming cold and warm requests survive launch lifecycle but leave cancels presented request',
    (tester) async {
      final states = StreamController<AuthState>.broadcast();
      final auth = _Auth();
      AuthState state = const AuthAuthenticated(userId: 'p', isOnboarded: true);
      when(() => auth.state).thenAnswer((_) => state);
      when(() => auth.stream).thenAnswer((_) => states.stream);
      var binds = 0;
      Completer<String>? pendingAuthorization;
      String? pendingId = 'request-1';
      final canceled = <String>[];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          canceled.add((call.arguments as Map)['id'] as String);
          return null;
        }
        return switch (call.method) {
          'beginSourceSession' => 1,
          'pending' =>
            pendingId == null
                ? null
                : {
                    'id': pendingId,
                    'mode': 'WEB',
                    'verifiedHosts': ['example.com'],
                    'usernameOnly': false,
                    'remainingMs': 30000,
                  },
          'bind' => 'bind-${++binds}',
          'authorizeUnlockedSession' =>
            pendingAuthorization?.future ?? 'session-authorization',
          _ => null,
        };
      });
      const claims = MemberSyncSessionAuthority(
        principalId: 'p',
        organizationId: 'o',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      );
      final source = AutoFillSourceAccessService(channel: channel);
      await source.begin(
        authority: claims,
        profileBinding: 'a' * 64,
        accountUnlock: const {},
      );
      final requests = AutoFillRequestController(
        source: source,
        channel: channel,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => claims,
          sessionRevision: () => 0,
        ),
      );
      // Production registers AuthBloc as a factory. The host must use the
      // app-owned provider, not create another unauthenticated session.
      var extraAuthCreations = 0;
      getIt.registerFactory<AuthBloc>(() {
        extraAuthCreations++;
        final other = _Auth();
        when(() => other.state).thenReturn(const AuthInitial());
        when(() => other.stream).thenAnswer((_) => const Stream.empty());
        return other;
      });
      getIt.registerSingleton<AutoFillSourceAccessService>(source);
      getIt.registerSingleton<AutoFillRequestController>(requests);
      getIt.registerSingleton<MemberSyncSessionAuthorityProvider>(
        MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => claims,
          sessionRevision: () => 0,
        ),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => AutoFillRequestHost(
              navigatorKey: navigator,
              prepare: () => throw StateError('unused'),
              requestPageBuilder: (_) => const Scaffold(body: Text('Picker')),
              child: child!,
            ),
            home: const Scaffold(body: Text('Locked')),
          ),
        ),
      );
      await requests.poll();
      await tester.pumpAndSettle();
      expect(requests.request?.id, 'request-1');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(requests.request?.id, 'request-1');
      expect(canceled, isEmpty);
      expect(find.text('Picker'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(binds, 1);
      expect(extraAuthCreations, 0);
      state = AuthAuthenticated(
        userId: 'p',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
      );
      states.add(state);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsOneWidget);
      expect(requests.isAuthorized, isTrue);
      expect(binds, 1);
      states.add(state);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsOneWidget);
      expect(binds, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(requests.request, isNull);
      expect(canceled, ['request-1']);
      // The placeholder has no real picker's request listener; close its route.
      navigator.currentState!.pop();
      pendingId = 'request-2';
      await requests.poll();
      await tester.pumpAndSettle();
      expect(binds, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(requests.request?.id, 'request-2');
      expect(canceled, ['request-1']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsOneWidget);
      state = AuthAuthenticated(
        userId: 'p',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
      );
      states.add(state);
      await tester.pumpAndSettle();
      expect(requests.isAuthorized, isFalse);
      expect(requests.request, isNull);
      expect(canceled, ['request-1', 'request-2']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      pendingAuthorization = Completer<String>();
      pendingId = 'request-3';
      await requests.poll();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsNothing);
      expect(requests.isAuthorized, isFalse);
      state = const AuthAuthenticated(userId: 'p', isOnboarded: true);
      states.add(state);
      await tester.pumpAndSettle();
      pendingAuthorization.complete('late-authorization');
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsNothing);
      expect(requests.request, isNull);
      expect(requests.isAuthorized, isFalse);
      expect(canceled, ['request-1', 'request-2', 'request-3']);
      pendingId = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      requests.dispose();
      await states.close();
    },
  );
}
