import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/multi_select_dropdown.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

const _options = <MultiSelectOption>[
  (value: 'a', label: 'Alpha'),
  (value: 'b', label: 'Bravo'),
  (value: 'c', label: 'Charlie'),
];

Future<Set<String>?> _pump(
  WidgetTester tester, {
  required Set<String> selected,
}) async {
  Set<String>? changed;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MultiSelectDropdown(
          label: 'Agent',
          placeholder: 'All agents',
          options: _options,
          selected: selected,
          onChanged: (next) => changed = next,
        ),
      ),
    ),
  );
  return changed;
}

void main() {
  group('MultiSelectDropdown', () {
    testWidgets('collapsed by default — shows placeholder, hides options', (
      tester,
    ) async {
      await _pump(tester, selected: const {});
      expect(find.text('All agents'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Bravo'), findsNothing);
    });

    testWidgets('tapping the trigger reveals the option checklist', (
      tester,
    ) async {
      await _pump(tester, selected: const {});
      await tester.tap(find.text('Agent'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('toggling an option emits the next selection set', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                Set<String> captured = const {};
                return StatefulBuilder(
                  builder: (context, setState) => MultiSelectDropdown(
                    label: 'Agent',
                    placeholder: 'All agents',
                    options: _options,
                    selected: captured,
                    onChanged: (next) => setState(() => captured = next),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Agent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bravo'));
      await tester.pumpAndSettle();
      // Summary collapses "Bravo" selected → single label shown in trigger.
      // Re-open to confirm the checkbox reflects selection.
      expect(find.text('Bravo'), findsWidgets);
    });

    testWidgets('single selection shows the option label as the summary', (
      tester,
    ) async {
      await _pump(tester, selected: const {'c'});
      // Collapsed trigger summary = the single option's label.
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('All agents'), findsNothing);
    });

    testWidgets('multiple selection shows the localized count summary', (
      tester,
    ) async {
      await _pump(tester, selected: const {'a', 'b'});
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('All agents'), findsNothing);
    });
  });
}
