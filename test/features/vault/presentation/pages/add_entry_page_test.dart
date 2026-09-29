import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/add_entry_page.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_widgets.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

void main() {
  setUp(() async {
    await getIt.reset();
    final repository = _MockEntryRepository();
    getIt.registerFactory<CreateEntryCubit>(
      () => CreateEntryCubit(repository: repository),
    );
  });

  tearDown(() => getIt.reset());

  testWidgets(
    'applying TOTP to an incomplete entry reports that it is not saved',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AddEntryPage(vaultId: 'vault'),
        ),
      );
      final add = find.text(l10n.totpAdd);
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      await tester.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)).first,
        'JBSWY3DPEHPK3PXP',
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text(l10n.entrySaveAction)),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.totpEntryIncomplete), findsOneWidget);
      expect(find.text(l10n.totpAdd), findsNothing);
      expect(find.byType(AddEntryPage), findsOneWidget);
    },
  );

  testWidgets('shows the explicitly selected Vault in the form header', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddEntryPage(vaultId: 'work-vault', vaultName: 'Work'),
      ),
    );
    expect(find.text('Work'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isFalse);
    expect(appBar.titleSpacing, 0);
  });

  testWidgets('card number and CVV are independently masked', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddEntryPage(vaultId: 'vault'),
      ),
    );

    await tester.tap(find.text(l10n.entryTypeCredential));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryTypeCreditCard).last);
    await tester.pumpAndSettle();

    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is OnboardingTextField && widget.label == label,
    );
    Finder input(String label) =>
        find.descendant(of: field(label), matching: find.byType(TextField));
    Finder toggle(String label) => find.descendant(
      of: field(label),
      matching: find.byType(EntryObscureToggle),
    );
    bool isObscured(String label) =>
        tester.widget<TextField>(input(label)).obscureText;

    final cardNumber = l10n.entryCardNumberLabel;

    expect(isObscured(cardNumber), isTrue);
    expect(isObscured(l10n.entryCvvLabel), isTrue);
    await tester.enterText(input(l10n.entryCvvLabel), '012');
    expect(find.text('PIN (optional)'), findsNothing);

    await tester.ensureVisible(toggle(cardNumber));
    await tester.tap(toggle(cardNumber));
    await tester.pump();
    expect(isObscured(cardNumber), isFalse);
    expect(isObscured(l10n.entryCvvLabel), isTrue);
    await tester.ensureVisible(toggle(l10n.entryCvvLabel));
    await tester.tap(toggle(l10n.entryCvvLabel));
    await tester.pump();
    expect(isObscured(l10n.entryCvvLabel), isFalse);
  });
}
