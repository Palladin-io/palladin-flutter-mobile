import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/shell/presentation/widgets/app_bottom_nav.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'library item is Entries with a key icon and remains the first slot',
    (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: AppBottomNav.tabEntries,
              onTap: (index) => selected = index,
            ),
          ),
        ),
      );
      expect(find.text('Entries'), findsOneWidget);
      expect(find.text('Vaults'), findsNothing);
      expect(find.byIcon(Icons.key), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Entries')).dx,
        lessThan(tester.getTopLeft(find.text('Agents')).dx),
      );
      await tester.tap(find.text('Entries'));
      expect(selected, AppBottomNav.tabEntries);
      expect(find.text('Settings'), findsOneWidget);
    },
  );
}
