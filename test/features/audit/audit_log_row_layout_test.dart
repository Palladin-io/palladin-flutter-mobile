import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/widgets/sheet_surface.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/audit_log_row.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  for (final width in [280.0, 800.0, 1200.0]) {
    testWidgets('chips use available width $width and date stays right', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: AuditLogRow(
                    entry: AuditLogEntry(
                      id: 'local-log',
                      eventType: AuditEventType.fromWire('entry-share.created'),
                      rawEventType: 'entry-share.created',
                      actorType: AuditActorType.user,
                      actorName: 'Local member',
                      entryLabel: 'Example entry',
                      resolvedVaultName: 'Example vault',
                      createdAt: DateTime.now(),
                    ),
                    agentNames: const {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final date = find.byWidgetPredicate(
        (widget) => widget is Text && widget.textAlign == TextAlign.right,
      );
      final rowRight = tester.getRect(find.byType(AuditLogRow)).right;
      expect(tester.getRect(date).right, closeTo(rowRight - 14, 0.1));
      expect(tester.takeException(), isNull);
      if (width == 1200) {
        expect(find.text('Example vault'), findsOneWidget);
        expect(find.text('Example entry'), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
      } else {
        final count = width == 280 ? '+2' : '+1';
        expect(find.text(count), findsOneWidget);
        expect(find.text('Example vault'), findsNothing);
        await tester.tap(find.text(count));
        await tester.pump();
        expect(find.text('Example vault'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.expand_less));
        await tester.pump();
        expect(find.text('Example vault'), findsNothing);
      }
    });
  }
  testWidgets('approval shows actor and agent and expands five context chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: AuditLogRow(
                entry: AuditLogEntry(
                  id: 'approval',
                  eventType: AuditEventType.grantApproved,
                  rawEventType: 'grant.approved',
                  actorType: AuditActorType.user,
                  actorName: 'Alex Morgan',
                  agentName: 'Claude Code',
                  entryLabel: 'GitHub',
                  resolvedVaultName: 'Work',
                  metadata: const {'method': 'inject'},
                  createdAt: DateTime.now(),
                ),
                agentNames: const {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining(
        'GitHub → Claude Code by Alex Morgan',
        findRichText: true,
      ),
      findsOneWidget,
    );
    final overflow = find.textContaining(RegExp(r'^\+[1-4]$'));
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pump();
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('inject'), findsOneWidget);
    await tester.tap(
      find.textContaining(
        'GitHub → Claude Code by Alex Morgan',
        findRichText: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SheetSurface), findsOneWidget);
    final fullSentence = find.descendant(
      of: find.byType(SheetSurface),
      matching: find.textContaining(
        'GitHub → Claude Code by Alex Morgan',
        findRichText: true,
      ),
    );
    expect(fullSentence, findsOneWidget);
    expect(tester.widget<RichText>(fullSentence).maxLines, isNull);
    expect(tester.takeException(), isNull);
  });
}
