import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_field_row.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('empty fields preserve row height without exposing actions', (
    tester,
  ) async {
    Widget field(String value) => EntryFieldRow(
      icon: Icons.link,
      value: value,
      isMasked: true,
      revealed: false,
      onToggleReveal: () {},
      onCopy: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(children: [field(''), field('synthetic-value')]),
        ),
      ),
    );
    final rows = find.byType(EntryFieldRow);
    expect(
      tester.getSize(rows.at(0)).height,
      tester.getSize(rows.at(1)).height,
    );
    expect(
      find.descendant(of: rows.at(0), matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: rows.at(0),
        matching: find.byType(EntrySmallIconButton),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: rows.at(1),
        matching: find.byType(EntrySmallIconButton),
      ),
      findsNWidgets(2),
    );
  });
}
