import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_log_format.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  const events = {
    'created': AppColors.vaultBlue,
    'delivered': AppColors.positiveAccent,
    'confirmed': AppColors.positiveAccent,
    'protection-changed': AppColors.vaultBlue,
    'expired': AppColors.textTertiary,
    'revoked': AppColors.brandRed,
    'ended': AppColors.textTertiary,
    'source-access-removed': AppColors.brandRed,
  };
  for (final event in events.entries) {
    test(
      'sharing ${event.key} has taxonomy, filters and localized sentence',
      () {
        final wire = 'entry-share.${event.key}';
        final type = AuditEventType.fromWire(wire);
        expect(type, isNot(AuditEventType.unknown));
        expect(auditEventColor(type), event.value);
        expect(AuditEventType.entryRelevant, contains(type));
        expect(AuditEventType.vaultGroups, contains(type.group));
        expect(AuditEventType.inGroup(type.group), hasLength(8));
        for (final locale in ['en', 'pl']) {
          final l10n = lookupAppLocalizations(Locale(locale));
          expect(auditEventLabel(l10n, type, wire), isNot(wire));
          final row = AuditLogEntry(
            id: 'log',
            eventType: type,
            rawEventType: wire,
            actorType: AuditActorType.user,
            actorName: 'Local member',
            resolvedObjectName: 'Local entry',
            localPresentationOnly: true,
            createdAt: DateTime(2026, 9, 21),
          );
          final sentence = auditEventSentence(l10n, row, const {});
          expect(sentence, isNotNull);
          expect(
            sentence!.map((part) => part.text).join(),
            contains('Local entry'),
          );
        }
      },
    );
  }
  for (final raw in [4, 'externalRecipient', 'ExternalRecipient']) {
    test('external actor $raw never impersonates a member or agent', () {
      final actor = AuditActorType.fromWire(raw);
      expect(actor, isNot(AuditActorType.unknown));
      final l10n = lookupAppLocalizations(const Locale('en'));
      final entry = AuditLogEntry(
        id: 'log',
        eventType: AuditEventType.fromWire('entry-share.confirmed'),
        rawEventType: 'entry-share.confirmed',
        actorType: actor,
        actorName: 'Wrong member',
        agentName: 'Wrong agent',
        userId: 'wrong-user',
        resolvedObjectName: 'Local entry',
        createdAt: DateTime(2026, 9, 21),
      );
      expect(auditActorName(l10n, entry, const {}), 'External recipient');
      final sentence = auditEventSentence(
        l10n,
        entry,
        const {},
      )!.map((part) => part.text).join();
      expect(sentence, contains('External recipient'));
      expect(sentence, contains('not proof of reading'));
      expect(sentence, isNot(contains('Wrong')));
      expect(sentence, isNot(contains('wrong-user')));
    });
  }
}
