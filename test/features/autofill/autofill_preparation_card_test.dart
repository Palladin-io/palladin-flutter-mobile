import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_service.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_preparation.dart';
import 'package:mobile_palladin/features/autofill/presentation/widgets/autofill_preparation_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Service extends Mock implements AutoFillCacheService {}

void main() {
  for (final (locale, brightness) in [
    for (final locale in ['en', 'pl'])
      for (final brightness in Brightness.values) (locale, brightness),
  ]) {
    testWidgets('$locale ${brightness.name}: branded progress and status', (
      tester,
    ) async {
      final service = _Service();
      final status = ValueNotifier(
        const AutoFillPreparation(AutoFillPreparationPhase.preparing),
      );
      addTearDown(status.dispose);
      when(() => service.preparation).thenReturn(status);
      when(service.retryPreparation).thenAnswer((_) async {});
      await tester.pumpWidget(
        RepositoryProvider<AutoFillCacheService>.value(
          value: service,
          child: MaterialApp(
            locale: Locale(locale),
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AutoFillPreparationCard()),
          ),
        ),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      status.value = const AutoFillPreparation(
        AutoFillPreparationPhase.preparing,
        examined: 2,
        total: 4,
      );
      await tester.pump();
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, .5);
      expect(
        tester.renderObject(find.byType(LinearProgressIndicator)),
        paints
          ..rect(color: AppColors.textTertiary.withValues(alpha: 0.15))
          ..rect(color: AppColors.brandRed),
      );
      final progressSemantics = tester.getSemantics(
        find.byType(LinearProgressIndicator),
      );
      expect(progressSemantics.getSemanticsData().value, '50');
      expect(
        progressSemantics.getSemanticsData().label,
        locale == 'en'
            ? 'Preparing 2 of 4 entries'
            : 'Przygotowywanie wpisów: 2 z 4',
      );
      status.value = const AutoFillPreparation(
        AutoFillPreparationPhase.publishing,
        examined: 4,
        total: 4,
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      status.value = const AutoFillPreparation(AutoFillPreparationPhase.failed);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text(locale == 'en' ? 'Retry' : 'Ponów'));
      verify(service.retryPreparation).called(1);
      status.value = const AutoFillPreparation(AutoFillPreparationPhase.ready);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining(
          locale == 'en' ? 'Passwords are prepared.' : 'Hasła są przygotowane.',
        ),
        findsOneWidget,
      );
    });
  }
}
