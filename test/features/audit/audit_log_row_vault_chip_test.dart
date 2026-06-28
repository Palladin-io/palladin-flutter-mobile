import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/widgets/audit_log_row.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

AuditLogEntry _entry({String? vaultId}) {
  return AuditLogEntry(
    id: 'log-1',
    // credential.accessed renders the legacy label (no sentence), so the vault
    // name only ever appears via the chip — not inside the row text.
    eventType: AuditEventType.credentialAccessed,
    rawEventType: 'credential.accessed',
    actorType: AuditActorType.agent,
    createdAt: DateTime(2026, 6, 1, 10),
    agentId: 'a-1',
    agentName: 'claude-code-01',
    vaultId: vaultId,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required bool showVaultChip,
  String? vaultId,
  Map<String, String> vaultNames = const {},
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AuditLogRow(
          entry: _entry(vaultId: vaultId),
          agentNames: const {},
          vaultNames: vaultNames,
          showVaultChip: showVaultChip,
        ),
      ),
    ),
  );
}

void main() {
  group('AuditLogRow vault chip', () {
    testWidgets('org scope shows the vault chip when the name is known', (
      tester,
    ) async {
      await _pump(
        tester,
        showVaultChip: true,
        vaultId: 'v-1',
        vaultNames: {'v-1': 'Production APIs'},
      );

      expect(find.text('Production APIs'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('per-vault tab (showVaultChip:false) renders no chip', (
      tester,
    ) async {
      await _pump(
        tester,
        showVaultChip: false,
        vaultId: 'v-1',
        vaultNames: {'v-1': 'Production APIs'},
      );

      expect(find.text('Production APIs'), findsNothing);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });

    testWidgets('unknown vault name → no chip (no raw id)', (tester) async {
      await _pump(
        tester,
        showVaultChip: true,
        vaultId: 'v-unknown',
        vaultNames: const {},
      );

      expect(find.byIcon(Icons.shield_outlined), findsNothing);
      expect(find.textContaining('v-unknown'), findsNothing);
    });

    testWidgets('no vaultId → no chip even in org scope', (tester) async {
      await _pump(tester, showVaultChip: true, vaultNames: const {});
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });
  });
}
