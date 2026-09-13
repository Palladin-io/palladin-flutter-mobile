import 'dart:async';

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

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
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
        final cubit = ConsentCubit(
          Remote(),
          MemoryActivationStore(),
          AnalyticsService(),
        );
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
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
          router.go('/settings/security');
          await tester.pumpAndSettle();
          expect(find.text('Security route'), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          await cubit.refresh();
          await tester.pumpAndSettle();
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
        } else {
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(router.routerDelegate.state.uri.path, '/');
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          await cubit.refresh();
          await tester.pumpAndSettle();
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
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
          final cubit = ConsentCubit(
            remote,
            MemoryActivationStore(),
            analytics,
          );
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
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
          verifyNever(() => auth.add(const PrivacyChoicesCompleted()));
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
