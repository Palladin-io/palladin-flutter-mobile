import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/verify_email_page.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/auth_brand_header.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class MockPasswordAuthRemoteDatasource extends Mock
    implements PasswordAuthRemoteDatasource {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockDefaultVaultProvisioner extends Mock
    implements DefaultVaultProvisioner {}

void main() {
  late MockPasswordAuthRemoteDatasource datasource;
  late MockAuthRepository authRepository;
  late AuthBloc authBloc;
  late MockDefaultVaultProvisioner defaultVaultProvisioner;

  setUp(() async {
    await getIt.reset();
    datasource = MockPasswordAuthRemoteDatasource();
    authRepository = MockAuthRepository();
    defaultVaultProvisioner = MockDefaultVaultProvisioner();
    when(() => authRepository.isAuthenticated()).thenAnswer((_) async => true);
    when(() => authRepository.getUserId()).thenAnswer((_) async => 'user-id');
    when(() => authRepository.isOnboarded()).thenAnswer((_) async => true);
    when(() => authRepository.getPermissions()).thenAnswer((_) async => 0);
    when(
      () => authRepository.getEmail(),
    ).thenAnswer((_) async => 'test@example.com');
    when(() => authRepository.isEmailVerified()).thenAnswer((_) async => false);
    when(() => authRepository.getAuthProvider()).thenAnswer((_) async => null);

    authBloc = AuthBloc(authRepository: authRepository)
      ..add(const AuthCheckRequested());
    await authBloc.stream.firstWhere((state) => state is AuthAuthenticated);

    getIt.registerFactory<VerifyEmailCubit>(
      () => VerifyEmailCubit(
        datasource: datasource,
        authRepository: authRepository,
        defaultVaultProvisioner: defaultVaultProvisioner,
      ),
    );
  });

  tearDown(() async {
    await authBloc.close();
    await getIt.reset();
  });

  testWidgets(
    'gate uses the delivery message as heading and orders all actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: const VerifyEmailPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Verify your email'), findsNothing);
      expect(
        find.text('We sent a verification link to test@example.com.'),
        findsOneWidget,
      );
      final message = find.text(
        'We sent a verification link to test@example.com.',
      );
      final header = find.byType(AuthBrandHeader);
      expect(
        tester.getTopLeft(message).dy - tester.getBottomLeft(header).dy,
        closeTo(AuthBrandHeader.formTopSpacing, 1),
      );

      final resend = find.text('Resend email');
      final checkAgain = find.text("I've verified my email");
      final signOut = find.text('Sign out');
      expect(resend, findsOneWidget);
      expect(checkAgain, findsOneWidget);
      expect(signOut, findsOneWidget);
      expect(
        tester.getCenter(resend).dy,
        lessThan(tester.getCenter(checkAgain).dy),
      );
      expect(
        tester.getCenter(checkAgain).dy,
        lessThan(tester.getCenter(signOut).dy),
      );
    },
  );
}
