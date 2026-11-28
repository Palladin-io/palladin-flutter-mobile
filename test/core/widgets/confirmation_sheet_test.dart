import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/confirmation_sheet.dart';
import 'package:mobile_palladin/core/widgets/sheet_drag_handle.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'confirmation keeps a compact grip and returns the selected decision',
    (tester) async {
      bool? decision;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  decision = await showModalBottomSheet<bool>(
                    context: context,
                    builder: (_) => const ConfirmationSheet(
                      title: 'Delete key',
                      message: 'This cannot be undone.',
                      confirmLabel: 'Delete',
                      cancelLabel: 'Cancel',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SheetDragHandle)).width, 36);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(decision, isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(decision, isTrue);
    },
  );
}
