import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

/// The Notification Center segment toggle renders All / To-do / History in that
/// order (mirroring the web). Grants is no longer a segment — it moved behind
/// the AppBar kebab. These guard the localized labels the toggle and kebab
/// depend on so a missing/empty key can't silently ship.
void main() {
  for (final locale in const [Locale('en'), Locale('pl')]) {
    final l10n = lookupAppLocalizations(locale);

    test('three segment labels are present and distinct (${locale.languageCode})', () {
      final labels = [l10n.inboxSegAll, l10n.inboxTodo, l10n.inboxHistory];
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
      expect(labels.toSet().length, 3, reason: 'segment labels must be unique');
    });

    test('kebab menu labels (Grants + Preferences) are present (${locale.languageCode})', () {
      expect(l10n.inboxGrantsMenu.trim(), isNotEmpty);
      expect(l10n.inboxPreferencesMenu.trim(), isNotEmpty);
      expect(l10n.inboxMoreActions.trim(), isNotEmpty);
    });
  }

  test('segment + kebab labels are localized per locale', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.inboxSegAll, 'All');
    expect(en.inboxGrantsMenu, 'Grants');
    expect(en.inboxPreferencesMenu, 'Notification preferences');

    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(pl.inboxSegAll, 'Wszystkie');
    expect(pl.inboxGrantsMenu, 'Granty');
    expect(pl.inboxPreferencesMenu, 'Ustawienia powiadomień');
  });
}
