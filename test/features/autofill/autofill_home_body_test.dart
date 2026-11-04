import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/widgets/brand_hero.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_service.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_preparation.dart';
import 'package:mobile_palladin/features/autofill/presentation/widgets/autofill_home_body.dart';
import 'package:mobile_palladin/features/autofill/presentation/widgets/autofill_preparation_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Service extends Mock implements AutoFillCacheService {}

void main() {
  for (final (locale, brightness) in [
    for (final locale in ['en', 'pl'])
      for (final brightness in Brightness.values) (locale, brightness),
  ]) {
    testWidgets('$locale ${brightness.name}: accessible dedicated Home body', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Service();
      final state = ValueNotifier(
        const AutoFillPreparation(
          AutoFillPreparationPhase.preparing,
          examined: 2,
          total: 4,
        ),
      );
      addTearDown(state.dispose);
      when(() => service.preparation).thenReturn(state);
      when(service.retryPreparation).thenAnswer((_) async {});
      var navigationTaps = 0;
      await tester.pumpWidget(
        RepositoryProvider<AutoFillCacheService>.value(
          value: service,
          child: MaterialApp(
            locale: Locale(locale),
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.5)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Home')),
              bottomNavigationBar: TextButton(
                onPressed: () => navigationTaps++,
                child: const Text('Vaults'),
              ),
              body: const AutoFillHomeBody(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      AutoFillPreparationCard(),
                      TextField(),
                      Text('Home content'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BrandHero), findsOneWidget);
      expect(find.text('Home content'), findsNothing);
      expect(find.text('Home').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byType(LinearProgressIndicator));
      await tester.pump();
      final semantics = tester
          .getSemantics(find.byType(LinearProgressIndicator))
          .getSemanticsData();
      expect(semantics.value, '50');
      expect(
        semantics.label,
        locale == 'en'
            ? 'Preparing 2 of 4 entries'
            : 'Przygotowywanie wpisów: 2 z 4',
      );
      await tester.tap(find.text('Vaults'));
      expect(navigationTaps, 1);
      expect(tester.takeException(), isNull);

      state.value = const AutoFillPreparation(AutoFillPreparationPhase.ready);
      await tester.pump();
      expect(find.text('Home content'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'synthetic query');
      tester.testTextInput.hide();
      state.value = const AutoFillPreparation(
        AutoFillPreparationPhase.checking,
      );
      await tester.pump();
      expect(find.text('synthetic query'), findsOneWidget);
      expect(find.byType(BrandHero), findsNothing);
      state.value = const AutoFillPreparation(AutoFillPreparationPhase.failed);
      await tester.pump();
      final retry = find.text(locale == 'en' ? 'Retry' : 'Ponów');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      verify(service.retryPreparation).called(1);
      state.value = const AutoFillPreparation(AutoFillPreparationPhase.unknown);
      await tester.pump();
      expect(find.text('Home content'), findsOneWidget);
      expect(find.byType(BrandHero), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
