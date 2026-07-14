import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/auth_legal_footer.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('renders localized Terms and Privacy links', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AuthLegalFooter()),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText));
    final text = richText.text.toPlainText();
    expect(text, contains('Terms'));
    expect(text, contains('Privacy Policy'));
  });
}
