import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_field_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    String value = 'synthetic-secret',
    Future<bool> Function()? check,
    bool enabled = true,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EntryShareFieldCard(
          label: 'Password',
          type: 'concealed',
          value: value,
          enabled: enabled,
          beforeReveal: check,
        ),
      ),
    ),
  );

  testWidgets('sensitive field needs explicit reveal and can be hidden again', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('synthetic-secret'), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('synthetic-secret'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(find.text('synthetic-secret'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets('denied or failed authority never reveals: error=$fails', (
      tester,
    ) async {
      await mount(
        tester,
        check: () async {
          if (fails) throw StateError('synthetic authority failure');
          return false;
        },
      );
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.text('synthetic-secret'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late authorization cannot reveal replacement field', (
    tester,
  ) async {
    final allowed = Completer<bool>();
    await mount(tester, check: () => allowed.future);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    await mount(tester, value: 'replacement-secret', check: () async => false);
    allowed.complete(true);
    await tester.pump();
    expect(find.text('synthetic-secret'), findsNothing);
    expect(find.text('replacement-secret'), findsNothing);
  });

  testWidgets('late authorization does not reveal a disabled field', (
    tester,
  ) async {
    final allowed = Completer<bool>();
    await mount(tester, check: () => allowed.future);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    await mount(tester, enabled: false, check: () => allowed.future);
    allowed.complete(true);
    await tester.pump();
    expect(find.text('synthetic-secret'), findsNothing);
  });

  testWidgets('late authorization after disposal is ignored', (tester) async {
    final allowed = Completer<bool>();
    await mount(tester, check: () => allowed.future);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpWidget(const SizedBox.shrink());
    allowed.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
