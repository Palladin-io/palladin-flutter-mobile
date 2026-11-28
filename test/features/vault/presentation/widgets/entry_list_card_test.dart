import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_list_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('simple compact row shows account and opens details', (
    tester,
  ) async {
    var expanded = 0;
    var opened = 0;
    var usernameReads = 0;
    final entry = EntryEntity(
      id: 'entry',
      vaultId: 'vault',
      label: 'GitHub',
      username: 'account',
      urlDomain: 'github.com',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EntryListCard(
            compact: true,
            entry: entry,
            isExpanded: false,
            payload: null,
            revealedFields: const {},
            onToggleReveal: () => expanded++,
            onToggleFieldReveal: (_, _) {},
            onCopy: (_) {},
            onEdit: () => opened++,
            loadUsername: () async {
              usernameReads++;
              return 'account';
            },
          ),
        ),
      ),
    );
    expect(find.text('github.com'), findsNothing);
    expect(find.text('account'), findsOneWidget);
    expect(usernameReads, 0);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(expanded, 0);
    expect(opened, 0);
    await tester.tap(find.text('GitHub'));
    expect(opened, 1);
  });

  for (final label in [
    'example.test',
    'https://example.test/',
    'Named account',
    'https://other.test/',
    'https://example.test/path',
  ]) {
    testWidgets('domain duplication for $label', (tester) async {
      final entry = EntryEntity(
        id: 'entry',
        vaultId: 'vault',
        label: label,
        username: 'account',
        urlDomain: 'example.test',
        type: EntryType.credential,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EntryListCard.selection(entry: entry, onSelect: () {}),
          ),
        ),
      );
      final duplicate =
          label == 'example.test' || label == 'https://example.test/';
      expect(
        find.text('example.test'),
        label == 'example.test' || !duplicate ? findsOneWidget : findsNothing,
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('account'), findsOneWidget);
    });
  }

  testWidgets(
    'selection refresh keeps pixels stable while blocking selection',
    (tester) async {
      final entry = EntryEntity(
        id: 'entry',
        vaultId: 'vault',
        label: 'example.test',
        username: 'a-long-synthetic-account-identifier@example.test',
        urlDomain: 'example.test',
        type: EntryType.credential,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      var enabled = true;
      var selections = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: SizedBox(
                  width: 320,
                  child: RepaintBoundary(
                    key: const ValueKey('selection-pixels'),
                    child: EntryListCard.selection(
                      entry: entry,
                      enabled: enabled,
                      onSelect: () => selections++,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      Future<List<int>> pixels() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('selection-pixels')),
        );
        final image = await boundary.toImage();
        try {
          return (await image.toByteData())!.buffer.asUint8List().toList();
        } finally {
          image.dispose();
        }
      }

      await tester.pumpAndSettle();
      final beforePixels = await tester.runAsync(pixels);
      final before = tester.getRect(find.text(entry.username!));
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text(entry.username!)), before);
      expect(
        listEquals(await tester.runAsync(pixels), beforePixels),
        isTrue,
        reason: 'Disabling selection must not change the rendered card',
      );
      await tester.tap(find.text(entry.username!));
      expect(selections, 0);
      await tester.tap(find.byIcon(Icons.arrow_forward));
      expect(selections, 0);
      update(() => enabled = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text(entry.username!)), before);
      await tester.tap(find.byIcon(Icons.arrow_forward));
      expect(selections, 1);
    },
  );

  testWidgets('same-name accounts show usernames and domain, not vault name', (
    tester,
  ) async {
    String? selected;
    EntryEntity account(String id) => EntryEntity(
      id: id,
      vaultId: 'vault',
      label: 'Broker',
      username: '$id@example.test',
      urlDomain: 'example.test',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              EntryListCard.selection(
                entry: account('first'),
                onSelect: () => selected = 'first',
              ),
              EntryListCard(
                entry: account('second'),
                vaultName: 'Private Vault',
                isExpanded: false,
                payload: null,
                revealedFields: const {},
                onToggleReveal: () {},
                onToggleFieldReveal: (_, _) {},
                onCopy: (_) {},
                onEdit: () => selected = 'second',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Broker'), findsNWidgets(2));
    expect(find.text('example.test'), findsNWidgets(2));
    expect(find.text('Private Vault'), findsNothing);
    await tester.tap(find.text('second@example.test'));
    expect(selected, 'second');
    await tester.tap(find.text('first@example.test'));
    expect(selected, 'first');
  });

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
  testWidgets('API and credential cards retain three equal-height lines', (
    tester,
  ) async {
    EntryEntity entry(EntryType type) => EntryEntity(
      id: type.name,
      vaultId: 'vault',
      label: type == EntryType.key ? 'Development API' : 'Account',
      type: type,
      username: type == EntryType.credential ? 'demo' : null,
      urlDomain: type == EntryType.credential ? 'example.test' : null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: Column(
              children: [
                EntryListCard.selection(
                  entry: entry(EntryType.key),
                  onSelect: () {},
                ),
                EntryListCard.selection(
                  entry: entry(EntryType.credential),
                  onSelect: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final cards = find.byType(EntryListCard);
    expect(
      tester.getSize(cards.at(0)).height,
      tester.getSize(cards.at(1)).height,
    );
    expect(
      find.descendant(of: cards.at(0), matching: find.text('—')),
      findsNWidgets(2),
    );
  });
}
