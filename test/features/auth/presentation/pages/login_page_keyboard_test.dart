import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/widgets/auth_legal_footer.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _LoginCubit extends MockCubit<LoginState> implements LoginCubit {}

void main() {
  for (final screenSize in [const Size(390, 844), const Size(360, 640)]) {
    testWidgets(
      'login footer stays out of the keyboard viewport at $screenSize',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = screenSize;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.reset);
        await getIt.reset();
        addTearDown(getIt.reset);
        final auth = _AuthBloc();
        whenListen(
          auth,
          const Stream<AuthState>.empty(),
          initialState: const AuthUnauthenticated(),
        );
        addTearDown(auth.close);
        final login = _LoginCubit();
        whenListen(
          login,
          const Stream<LoginState>.empty(),
          initialState: const LoginInitial(),
        );
        getIt.registerFactory<LoginCubit>(() => login);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BlocProvider<AuthBloc>.value(
              value: auth,
              child: const LoginPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.continueWithEmail));
        await tester.pumpAndSettle();
        final footerBeforeKeyboard = tester.getRect(
          find.byType(AuthLegalFooter),
        );

        await tester.enterText(
          find.byType(TextField).first,
          'user@example.com',
        );
        await tester.enterText(find.byType(TextField).last, 'example password');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.view.padding = FakeViewPadding.zero;
        await tester.pumpAndSettle();

        expect(find.byType(AuthLegalFooter), findsNothing);
        final submit = find.widgetWithText(
          ElevatedButton,
          l10n.authLoginButton,
        );
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);
        expect(
          tester.getBottomRight(submit).dy,
          lessThanOrEqualTo(screenSize.height - 300),
        );
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'user@example.com',
        );
        expect(tester.takeException(), isNull);

        tester.view.viewInsets = FakeViewPadding.zero;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        await tester.pumpAndSettle();
        expect(find.byType(AuthLegalFooter), findsOneWidget);
        expect(
          tester.getRect(find.byType(AuthLegalFooter)),
          footerBeforeKeyboard,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
