import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_list_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  for (final global in [false, true]) {
    testWidgets('shared card actions fit 320px, global=$global', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var show = 0, details = 0, share = 0;
      final entry = EntryEntity(
        id: 'entry',
        vaultId: 'vault',
        label: 'A long synthetic entry name that must stay within the card',
        type: EntryType.credential,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: EntryListCard(
                entry: entry,
                isExpanded: false,
                payload: null,
                vaultName: global ? 'A long synthetic Vault name' : null,
                revealedFields: const {},
                onToggleReveal: () => show++,
                onToggleFieldReveal: (_, _) {},
                onCopy: (_) {},
                onEdit: () => details++,
                onShare: () => share++,
              ),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(EntryListCard)),
      )!;
      await tester.tap(find.byTooltip(l10n.vaultRevealEntry));
      await tester.tap(find.byTooltip(l10n.vaultViewEntry));
      await tester.tap(find.byTooltip(l10n.sharingShareEntry));
      expect([show, details, share], [1, 1, 1]);
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byIcon(Icons.visibility)).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.share_outlined)).dx),
      );
      expect(
        tester.getCenter(find.byIcon(Icons.share_outlined)).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.arrow_forward)).dx),
      );
      final row = tester.getRect(find.byType(EntryListCard));
      expect(
        tester.getRect(find.byIcon(Icons.share_outlined)).right,
        lessThan(row.right),
      );
    });
  }
}
