import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/settings/presentation/widgets/open_source_licenses_section.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('opens Flutter licence registry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: OpenSourceLicensesSection()),
      ),
    );

    await tester.tap(find.text('Open-source licences'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
