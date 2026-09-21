import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/widgets/auth_brand_header.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';
import 'package:mobile_palladin/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mobile_palladin/features/onboarding/presentation/cubit/onboarding_cubit.dart';
import 'package:mobile_palladin/features/onboarding/presentation/pages/master_password_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements OnboardingRepository {}

class _Hibp extends Mock implements HibpService {}

void main() {
  setUp(() {
    getIt.registerSingleton<HibpService>(_Hibp());
  });
  tearDown(() async => getIt.reset());

  for (final locale in ['en', 'pl']) {
    testWidgets('master password form scrolls above the keyboard ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 744);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final cubit = OnboardingCubit(repository: _Repository());
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: locale == 'pl' ? Brightness.light : Brightness.dark,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(locale == 'pl' ? 1.5 : 1)),
            child: child!,
          ),
          home: BlocProvider.value(
            value: cubit,
            child: const MasterPasswordPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterPasswordPage)),
      )!;
      final brandBottom = tester.getBottomLeft(find.byType(AuthBrandHeader)).dy;
      final firstFieldTop = tester
          .getTopLeft(find.text(l10n.onboardingMasterPasswordLabel))
          .dy;
      expect(firstFieldTop - brandBottom, AuthBrandHeader.denseFormTopSpacing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byType(TextField).first);
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .focusNode!
            .hasFocus,
        isTrue,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      final headerBeforeScroll = tester.getRect(find.byType(AuthBrandHeader));
      final footerBeforeScroll = tester.getRect(find.byType(PrimaryButton));
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(PrimaryButton)), footerBeforeScroll);
      final headerAfterScroll = tester.getRect(find.byType(AuthBrandHeader));
      expect(headerAfterScroll.size, headerBeforeScroll.size);
      expect(headerAfterScroll.top, lessThan(headerBeforeScroll.top));
      expect(footerBeforeScroll.bottom, lessThanOrEqualTo(744 - 250));
      expect(
        tester.getRect(find.byType(TextField).last).bottom,
        lessThanOrEqualTo(footerBeforeScroll.top),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
