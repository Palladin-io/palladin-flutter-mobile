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

  testWidgets('credit card secrets can be revealed independently', (
    tester,
  ) async {
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
    final securityCode = l10n.entrySecurityCodeLabel;
    final pin = l10n.entryPinLabel;

    expect(isObscured(cardNumber), isTrue);
    expect(isObscured(securityCode), isTrue);
    expect(isObscured(pin), isTrue);

    await tester.ensureVisible(toggle(cardNumber));
    await tester.tap(toggle(cardNumber));
    await tester.pump();
    expect(isObscured(cardNumber), isFalse);
    expect(isObscured(securityCode), isTrue);
    expect(isObscured(pin), isTrue);

    await tester.ensureVisible(toggle(securityCode));
    await tester.tap(toggle(securityCode));
    await tester.pump();
    expect(isObscured(cardNumber), isFalse);
    expect(isObscured(securityCode), isFalse);
    expect(isObscured(pin), isTrue);

    await tester.ensureVisible(toggle(pin));
    await tester.tap(toggle(pin));
    await tester.pump();
    expect(isObscured(cardNumber), isFalse);
    expect(isObscured(securityCode), isFalse);
    expect(isObscured(pin), isFalse);
  });
}
