import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_protection_sheet.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  late ValueNotifier<int> epoch;
  setUp(() => epoch = ValueNotifier(0));
  tearDown(() => epoch.dispose());

  Future<void> pump(
    WidgetTester tester, {
    EntryShareProtection protection = EntryShareProtection.password,
    required Future<bool> Function(EntryShareProtection, String?) onSave,
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EntryShareProtectionSheet(
            protection: protection,
            authorityEpoch: epoch,
            onSave: onSave,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );
  Future<void> enter(WidgetTester tester, String secret, String confirm) async {
    await tester.enterText(field('sharing-protection-secret'), secret);
    await tester.enterText(field('sharing-protection-confirmation'), confirm);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'secret starts empty and masked; failed submit clears both inputs',
    (tester) async {
      final calls = <(EntryShareProtection, String?)>[];
      await pump(
        tester,
        onSave: (p, s) async {
          calls.add((p, s));
          return false;
        },
      );
      for (final text in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(text.obscureText, true);
        expect(text.controller!.text, isEmpty);
      }
      await enter(tester, '  synthetic secret  ', '  synthetic secret  ');
      await save(tester);
      expect(calls, [(EntryShareProtection.password, '  synthetic secret  ')]);
      expect(
        find.textContaining('Could not change protection'),
        findsOneWidget,
      );
      for (final text in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(text.controller!.text, isEmpty);
      }
    },
  );
  testWidgets('confirmation mismatch blocks request with animated feedback', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      onSave: (_, _) async {
        calls++;
        return false;
      },
    );
    await enter(tester, 'synthetic password', 'different password');
    await save(tester);
    expect(calls, 0);
    expect(find.text('The values do not match.'), findsOneWidget);
    expect(find.byType(FieldFeedbackSlot), findsWidgets);
  });
  testWidgets('obvious PIN cannot be submitted', (tester) async {
    var calls = 0;
    await pump(
      tester,
      protection: EntryShareProtection.pin,
      onSave: (_, _) async {
        calls++;
        return false;
      },
    );
    await enter(tester, '123456', '123456');
    await save(tester);
    expect(calls, 0);
    expect(find.textContaining('Avoid repeated digits'), findsOneWidget);
  });
  testWidgets('removing protection sends null, never an old secret', (
    tester,
  ) async {
    final calls = <(EntryShareProtection, String?)>[];
    await pump(
      tester,
      protection: EntryShareProtection.none,
      onSave: (p, s) async {
        calls.add((p, s));
        return false;
      },
    );
    expect(find.byType(TextField), findsNothing);
    await save(tester);
    expect(calls, [(EntryShareProtection.none, null)]);
  });
  testWidgets('duplicate taps are blocked while pending', (tester) async {
    var calls = 0;
    final result = Completer<bool>();
    await pump(
      tester,
      onSave: (_, _) {
        calls++;
        return result.future;
      },
    );
    await enter(tester, 'synthetic password', 'synthetic password');
    await save(tester);
    expect(find.text('Saving…'), findsOneWidget);
    await tester.tap(find.text('Saving…'));
    expect(calls, 1);
    result.complete(false);
    await tester.pumpAndSettle();
  });
  testWidgets(
    'retirement wipes controllers and rejects a late successful response',
    (tester) async {
      final result = Completer<bool>();
      await pump(tester, onSave: (_, _) => result.future);
      await enter(tester, 'synthetic password', 'synthetic password');
      await save(tester);
      epoch.value++;
      await tester.pumpAndSettle();
      for (final text in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(text.controller!.text, isEmpty);
        expect(text.enabled, false);
      }
      result.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(EntryShareProtectionSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Polish controls and pinned equal-height actions render at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, locale: 'pl', onSave: (_, _) async => false);
      expect(find.text('Zmień zabezpieczenie'), findsOneWidget);
      final cancel = find.widgetWithText(OutlinedButton, 'Anuluj');
      final saveButton = find.widgetWithText(OutlinedButton, 'Zapisz');
      expect(tester.getSize(cancel).height, tester.getSize(saveButton).height);
      expect(tester.takeException(), isNull);
    },
  );
}
