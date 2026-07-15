import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(AuthLegalFooter),
        matching: find.byType(RichText),
      ),
    );
    final text = richText.text.toPlainText();
    expect(text, contains('Terms'));
    expect(text, contains('Privacy Policy'));
  });

  testWidgets('shows the localized error when the platform launcher throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AuthLegalFooter(
            launcher: (uri, {required mode}) async {
              throw PlatformException(code: 'launch-failed');
            },
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(AuthLegalFooter),
        matching: find.byType(RichText),
      ),
    );
    final terms = _firstRecognizableSpan(richText.text as TextSpan);
    (terms.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Unable to open this link.'), findsOneWidget);
  });
}

TextSpan _firstRecognizableSpan(TextSpan span) {
  if (span.recognizer != null) return span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child case final TextSpan childSpan) {
      try {
        return _firstRecognizableSpan(childSpan);
      } on StateError {
        continue;
      }
    }
  }
  throw StateError('No recognizable legal link found');
}
