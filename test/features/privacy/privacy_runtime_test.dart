import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
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
          initialLocation: explicitSettings
              ? '/settings/privacy'
              : '/settings/security',
          routes: [
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
          await cubit.refresh();
          await tester.pumpAndSettle();
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
        } else {
          verify(() => auth.add(const PrivacyChoicesRequested())).called(1);
          await cubit.refresh();
          await tester.pumpAndSettle();
          verifyNever(() => auth.add(const PrivacyChoicesRequested()));
        }
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        if (!cubit.isClosed) await cubit.close();
        await auth.close();
      },
    );
  }
}
