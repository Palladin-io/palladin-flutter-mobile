import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_claw_vault/features/notifications/presentation/widgets/notification_format.dart';
import 'package:mobile_claw_vault/l10n/generated/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  InboxNotification make(
    String type, {
    Map<String, dynamic> metadata = const {},
    NotificationCategory category = NotificationCategory.actionRequired,
    NotificationActionState actionState = NotificationActionState.pending,
  }) {
    return InboxNotification(
      id: 'n',
      type: type,
      category: category,
      titleKey: type,
      metadata: metadata,
      actionState: actionState,
      occurredAt: DateTime(2026, 6, 17),
    );
  }

  const allTypes = [
    'grant_pending',
    'agent_pending',
    'agent_approved',
    'credential_stale',
    'grant_approved',
    'grant_revoked',
    'grant_denied',
    'future_unknown_type',
  ];

  test('every type renders exactly 3 detail rows', () {
    for (final type in allTypes) {
      final rows = notificationRows(l10n, make(type));
      expect(rows.length, 3, reason: '$type should have 3 rows');
    }
  });

  test('missing values fall back to the — placeholder, never drop a row', () {
    // No metadata at all → all value cells are the placeholder.
    final rows = notificationRows(l10n, make('grant_pending'));
    expect(rows.every((r) => r.value == l10n.notifPlaceholder), isTrue);
    expect(rows.map((r) => r.label), [
      l10n.notifRowEntry,
      l10n.notifRowMethods,
      l10n.notifRowReason,
    ]);
  });

  test('agent_approved drops the "By" row (identity rows only)', () {
    final rows = notificationRows(
      l10n,
      make(
        'agent_approved',
        metadata: const {'agentId': 'a-1', 'actorName': 'Patryk'},
        category: NotificationCategory.update,
        actionState: NotificationActionState.resolved,
      ),
    );
    expect(rows.map((r) => r.label), [
      l10n.notifRowPublicKey,
      l10n.notifRowAgentId,
      l10n.notifRowHostIp,
    ]);
    expect(rows.any((r) => r.label == l10n.notifRowBy), isFalse);
  });

  test('grant_approved Access row: uses left, expiry, or unlimited', () {
    final usesRow = notificationRows(
      l10n,
      make(
        'grant_approved',
        metadata: const {'queryLimit': '20', 'queryCount': '2'},
      ),
    ).firstWhere((r) => r.label == l10n.notifRowAccess);
    expect(usesRow.value, l10n.orgGrantUsesLeft(18, 20));

    final expiryRow = notificationRows(
      l10n,
      make('grant_approved', metadata: const {'expiresAt': '2026-07-01T00:00:00Z'}),
    ).firstWhere((r) => r.label == l10n.notifRowAccess);
    expect(expiryRow.value, l10n.orgGrantExpiresOn('2026-07-01'));

    final unlimitedRow = notificationRows(l10n, make('grant_approved'))
        .firstWhere((r) => r.label == l10n.notifRowAccess);
    expect(unlimitedRow.value, l10n.notifAccessUnlimited);
  });
}
