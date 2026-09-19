import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_runtime.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'privacy_fixture.dart';
import 'package:mobile_palladin/core/l10n/locale_cubit.dart';
import 'package:mobile_palladin/core/theme/theme_cubit.dart';
import 'package:mobile_palladin/features/shell/presentation/widgets/settings_drawer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/analytics/analytics_service_test.dart' show CaptureAdapter;

class _Theme extends MockCubit<ThemeMode> implements ThemeCubit {}

class _Locale extends MockCubit<Locale> implements LocaleCubit {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  testWidgets(
    'Privacy in the drawer preserves route and edited input, and does not prompt again on polling',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      final auth = _Auth();
      when(() => auth.state).thenReturn(
        const AuthAuthenticated(
          userId: 'account',
          isOnboarded: true,
          emailVerified: true,
          isVaultLocked: false,
        ),
      );
      final theme = _Theme();
      when(() => theme.state).thenReturn(ThemeMode.light);
      final locale = _Locale();
      when(() => locale.state).thenReturn(const Locale('en'));
      final remote = Remote()..current = consent(status: 'denied', revision: 1);
      final cubit = ConsentCubit(remote, AnalyticsService());
      final router = GoRouter(
        initialLocation: '/form',
        routes: [
          GoRoute(
            path: '/form',
            builder: (_, _) => Scaffold(
              endDrawer: const SettingsDrawer(),
              appBar: AppBar(title: const Text('Editing')),
              body: const TextField(
                decoration: InputDecoration(labelText: 'Draft'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider.value(value: cubit),
            BlocProvider<ThemeCubit>.value(value: theme),
            BlocProvider<LocaleCubit>.value(value: locale),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) =>
                PrivacyRuntime(router: router, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsaved draft');
      tester.state<ScaffoldState>(find.byType(Scaffold)).openEndDrawer();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(router.routerDelegate.state.uri.path, '/form');
      remote.current = consent();
      await cubit.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Unsaved draft'), findsOneWidget);
      expect(router.routerDelegate.state.uri.path, '/form');
      await cubit.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(remote.decisions, isEmpty);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      if (!cubit.isClosed) await cubit.close();
      await auth.close();
      await theme.close();
      await locale.close();
    },
  );

  for (final blockedPath in [
    '/register',
    '/onboarding',
    '/verify-email',
    '/unlock',
    '/recovery',
  ]) {
    testWidgets(
      'offers choices only after leaving $blockedPath for the ready app',
      (tester) async {
        final auth = _Auth();
        var currentAuth = const AuthAuthenticated(
          userId: 'account',
          isOnboarded: false,
          emailVerified: false,
          isVaultLocked: true,
        );
        when(() => auth.state).thenAnswer((_) => currentAuth);
        final remote = Remote();
        final cubit = ConsentCubit(remote, AnalyticsService());
        final router = GoRouter(
          initialLocation: blockedPath,
          routes: [
            GoRoute(
              path: blockedPath,
              builder: (_, _) => const Scaffold(body: Text('Auth flow')),
            ),
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Home')),
            ),
          ],
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider.value(value: cubit),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) =>
                  PrivacyRuntime(router: router, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        // Even after auth becomes ready, the outgoing registration/result screen
        // is not a place to present optional choices during navigation.
        currentAuth = currentAuth.copyWith(
          isOnboarded: true,
          emailVerified: true,
          isVaultLocked: false,
        );
        await cubit.refresh();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        // Missing notices should not interrupt the first actual app entry either.
        remote.current = const UserConsent(
          purpose: 'product_analytics',
          scope: 'palladin_web_mobile',
          status: 'unknown',
          revision: 0,
          activationRevision: 0,
        );
        await cubit.refresh();
        router.go('/');
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        remote.current = consent();
        await cubit.refresh();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(router.routerDelegate.state.uri.path, '/');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await cubit.refresh();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(remote.decisions, isEmpty);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        if (!cubit.isClosed) await cubit.close();
        await auth.close();
      },
    );
  }
  for (final shell in [false, true]) {
    testWidgets(
      'imperative pageviews use visible templates, dedupe and redact IDs/query/fragment: shell=$shell',
      (tester) async {
        final auth = _Auth();
        when(() => auth.state).thenReturn(
          const AuthAuthenticated(
            userId: 'account',
            isOnboarded: true,
            emailVerified: true,
            isVaultLocked: false,
          ),
        );
        final adapter = CaptureAdapter();
        final analytics =
            AnalyticsService(transport: Dio()..httpClientAdapter = adapter)
              ..configure(
                projectKey: 'test-project',
                host: 'https://eu.i.posthog.com',
                released: true,
              );
        final remote = Remote()
          ..current = consent(
            status: 'granted',
            revision: 1,
            activationRevision: 1,
          );
        final cubit = ConsentCubit(remote, analytics);
        final routes = [
          GoRoute(
            path: '/vaults',
            builder: (_, _) => const Scaffold(body: Text('Vaults')),
            routes: [
              GoRoute(
                path: ':vaultId',
                builder: (_, _) => const Scaffold(body: Text('Vault detail')),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) =>
                        const Scaffold(body: Text('Vault settings')),
                  ),
                ],
              ),
            ],
          ),
        ];
        final router = GoRouter(
          initialLocation: '/vaults',
          routes: shell
              ? [ShellRoute(builder: (_, _, child) => child, routes: routes)]
              : routes,
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider.value(value: cubit),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (_, child) => PrivacyRuntime(
                router: router,
                analytics: analytics,
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expected = ['/vaults'];
        void expectRoutes() => expect(
          adapter.payloads.map((p) => p['properties']['route']),
          expected,
        );
        expectRoutes();
        Future<void> push(String from, String path) async {
          unawaited(tester.element(find.text(from)).push<void>(path));
          await tester.pumpAndSettle();
        }

        await push(
          'Vaults',
          '/vaults/private-vault-123?email=secret%40example.test#private-fragment',
        );
        expected.add('/vaults/:vaultId');
        expectRoutes();
        await push(
          'Vault detail',
          '/vaults/private-vault-123/settings?token=secret-token#private-fragment',
        );
        expected.add('/vaults/:vaultId/settings');
        expectRoutes();
        // Consent refreshes notify the runtime without changing the visible screen.
        await cubit.refresh();
        await tester.pumpAndSettle();
        expectRoutes();
        await push(
          'Vault settings',
          '/vaults/private-vault-456/settings?email=second%40example.test#second-fragment',
        );
        expectRoutes();
        router.pop();
        await tester.pumpAndSettle();
        expectRoutes();
        router.pop();
        await tester.pumpAndSettle();
        expected.add('/vaults/:vaultId');
        expectRoutes();
        router.pop();
        await tester.pumpAndSettle();
        expected.add('/vaults');
        expectRoutes();
        expect(
          adapter.payloads.every((p) => p['event'] == r'$pageview'),
          isTrue,
        );
        final wire = jsonEncode(adapter.payloads);
        for (final private in [
          'private-vault',
          'secret',
          'example.test',
          'fragment',
          '?',
          '#',
        ]) {
          expect(wire, isNot(contains(private)));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        if (!cubit.isClosed) await cubit.close();
        await analytics.reset();
        await auth.close();
      },
    );
  }
  for (final explicitSettings in [true, false]) {
    testWidgets(
      'first-entry prompt does not stack or recur after explicit privacy route: $explicitSettings',
      (tester) async {
        final auth = _Auth();
        when(() => auth.state).thenReturn(
          const AuthAuthenticated(
            userId: 'account',
            isOnboarded: true,
            emailVerified: true,
            isVaultLocked: false,
          ),
        );
        final cubit = ConsentCubit(Remote(), AnalyticsService());
        final router = GoRouter(
          initialLocation: explicitSettings ? '/settings/privacy' : '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Home')),
            ),
            GoRoute(
              path: '/settings/privacy',
              builder: (_, _) => const Scaffold(body: Text('Privacy route')),
            ),
            GoRoute(
              path: '/settings/security',
              builder: (_, _) => const Scaffold(body: Text('Security route')),
            ),
          ],
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider.value(value: cubit),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  PrivacyRuntime(router: router, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (explicitSettings) {
          router.go('/settings/security');
          await tester.pumpAndSettle();
          expect(find.text('Security route'), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          await cubit.refresh();
          await tester.pumpAndSettle();
        } else {
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(router.routerDelegate.state.uri.path, '/');
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          await cubit.refresh();
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        if (!cubit.isClosed) await cubit.close();
        await auth.close();
      },
    );
  }
  for (final slowRead in [false, true]) {
    for (final save in [false, true]) {
      testWidgets(
        'delayed poll preserves form route, input and return stack: slow=$slowRead save=$save',
        (tester) async {
          final auth = _Auth();
          when(() => auth.state).thenReturn(
            const AuthAuthenticated(
              userId: 'account',
              isOnboarded: true,
              emailVerified: true,
              isVaultLocked: false,
            ),
          );
          final remote = Remote()
            ..networkFails = !slowRead
            ..pendingRead = slowRead ? Completer<UserConsents>() : null;
          final analytics = AnalyticsService();
          final cubit = ConsentCubit(remote, analytics);
          final router = GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('Origin')),
              ),
              GoRoute(
                path: '/edit',
                builder: (_, _) => const Scaffold(body: TextField()),
              ),
            ],
          );
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: auth),
                BlocProvider.value(value: cubit),
              ],
              child: MaterialApp.router(
                routerConfig: router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (_, child) =>
                    PrivacyRuntime(router: router, child: child!),
              ),
            ),
          );
          await tester.pumpAndSettle();
          unawaited(router.push('/edit?step=credentials'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'unsaved input');
          final originalInput = tester.state(find.byType(EditableText));
          expect(find.byType(BottomSheet), findsNothing);
          remote.networkFails = false;
          if (slowRead) {
            remote.pendingRead!.complete(UserConsents([remote.current], 60));
            remote.pendingRead = null;
          } else {
            // Exercise the actual periodic recovery, not a direct call to refresh.
            await tester.pump(const Duration(seconds: 30));
          }
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(
            router.routerDelegate.state.uri.toString(),
            '/edit?step=credentials',
          );
          expect(
            tester.state(find.byType(EditableText, skipOffstage: false)),
            same(originalInput),
          );
          await tester.tap(
            save ? find.text('Save choice') : find.byTooltip('Close'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('unsaved input'), findsOneWidget);
          expect(tester.state(find.byType(EditableText)), same(originalInput));
          expect(
            router.routerDelegate.state.uri.toString(),
            '/edit?step=credentials',
          );
          expect(router.canPop(), isTrue);
          await cubit.refresh();
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(analytics.isInitialized, isFalse);
          expect(AnalyticsService.instance.isInitialized, isFalse);
          router.pop();
          await tester.pumpAndSettle();
          expect(find.text('Origin'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          if (!cubit.isClosed) await cubit.close();
          await auth.close();
        },
      );
    }
  }
}
