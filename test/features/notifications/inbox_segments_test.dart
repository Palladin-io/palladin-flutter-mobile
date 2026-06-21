import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/l10n/generated/app_localizations.dart';

/// The Notification Center segment toggle renders To-do / History / Grants in
/// that order (Grants last, mirroring the web). These guard the localized
/// labels the toggle depends on so a missing/empty key can't silently ship.
void main() {
  for (final locale in const [Locale('en'), Locale('pl')]) {
    final l10n = lookupAppLocalizations(locale);

    test('all three segment labels are present and distinct (${locale.languageCode})', () {
      final labels = [l10n.inboxTodo, l10n.inboxHistory, l10n.inboxSegGrants];
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
      expect(labels.toSet().length, 3, reason: 'segment labels must be unique');
    });
  }

  test('Grants segment label is localized per locale', () {
    expect(lookupAppLocalizations(const Locale('en')).inboxSegGrants, 'Grants');
    expect(lookupAppLocalizations(const Locale('pl')).inboxSegGrants, 'Granty');
  });
}
