import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/verify_email_page.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_onboarding_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

import '../../features/privacy/privacy_fixture.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Datasource extends Mock implements PasswordAuthRemoteDatasource {}

class _Repository extends Mock implements AuthRepository {}

class _Provisioner extends Mock implements DefaultVaultProvisioner {}

void main() {
  for (final onboarded in [false, true]) {
    testWidgets(
      'verification token reaches real cubit before optional privacy (onboarded: $onboarded)',
      (tester) async {
        await getIt.reset();
        final auth = _AuthBloc();
        when(() => auth.state).thenReturn(
          AuthAuthenticated(
            userId: 'account',
            isOnboarded: onboarded,
            emailVerified: false,
            needsPrivacyChoices: true,
          ),
        );
        final datasource = _Datasource();
        const token = 'fixture+token/with=query';
        when(() => datasource.verifyEmail(token)).thenAnswer((_) async {});
        getIt.registerFactory<VerifyEmailCubit>(
          () => VerifyEmailCubit(
            datasource: datasource,
            authRepository: _Repository(),
            defaultVaultProvisioner: _Provisioner(),
          ),
        );
        final consents = ConsentCubit(
          Remote(),
          MemoryActivationStore(),
          AnalyticsService(),
        );
        await consents.bind('account', 'en');
        final router = createRouter(auth);
        final destination = Uri(
          path: '/verify-email',
          queryParameters: {'token': token},
        );
        router.go(destination.toString());
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider.value(value: consents),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri, destination);
        expect(
          tester.widget<VerifyEmailPage>(find.byType(VerifyEmailPage)).token,
          token,
        );
        verify(() => datasource.verifyEmail(token)).called(1);
        expect(find.byType(PrivacyOnboardingPage), findsNothing);
        // After leaving the verification result the optional step is still offered.
        router.go('/');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/privacy-choices',
        );
        expect(find.byType(PrivacyOnboardingPage), findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await auth.close();
        await consents.close();
        await getIt.reset();
      },
    );
  }
}
