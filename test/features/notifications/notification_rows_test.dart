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

  test('every type renders its web-parity rows (1–4, never empty)', () {
    const expectedCount = {
      'grant_pending': 3,
      'agent_pending': 4,
      'agent_approved': 4,
      'credential_stale': 3,
      'grant_approved': 4,
      'grant_revoked': 3,
      'grant_denied': 4,
      'future_unknown_type': 3,
    };
    for (final type in allTypes) {
      final rows = notificationRows(l10n, make(type));
      expect(rows, isNotEmpty, reason: '$type should never be empty');
      expect(rows.length, lessThanOrEqualTo(4), reason: '$type exceeds 4 rows');
      expect(rows.length, expectedCount[type], reason: '$type row count');
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

  test('agent_approved shows Agent Id, Type, Host · Ip, By (web parity)', () {
    final rows = notificationRows(
      l10n,
      make(
        'agent_approved',
        metadata: const {
          'agentId': 'a-1',
          'agentType': 'ci',
          'actorName': 'Patryk',
        },
        category: NotificationCategory.update,
        actionState: NotificationActionState.resolved,
      ),
    );
    expect(rows.map((r) => r.label), [
      l10n.notifRowAgentId,
      l10n.notifRowType,
      l10n.notifRowHostIp,
      l10n.notifRowBy,
    ]);
  });

  test('grant_approved shows Entry, Methods, Reason, By (web parity)', () {
    final rows = notificationRows(
      l10n,
      make(
        'grant_approved',
        metadata: const {
          'methods': 'Get, Exec',
          'reason': 'deploy',
          'actorName': 'Patryk',
        },
      ),
    );
    expect(rows.map((r) => r.label), [
      l10n.notifRowEntry,
      l10n.notifRowMethods,
      l10n.notifRowReason,
      l10n.notifRowBy,
    ]);
  });

  test('grant_denied shows Entry, Methods, Reason(denyReason), By', () {
    final rows = notificationRows(
      l10n,
      make(
        'grant_denied',
        metadata: const {
          'methods': 'Get',
          'denyReason': 'not allowed',
          'actorName': 'Patryk',
        },
      ),
    );
    expect(rows.map((r) => r.label), [
      l10n.notifRowEntry,
      l10n.notifRowMethods,
      l10n.notifRowReason,
      l10n.notifRowBy,
    ]);
    expect(rows[2].value, 'not allowed');
  });

  group('agent avatar header', () {
    test('agent-bearing types use the real agent avatar', () {
      for (final type in const [
        'grant_pending',
        'grant_approved',
        'grant_revoked',
        'grant_denied',
        'agent_pending',
        'agent_approved',
      ]) {
        expect(
          notificationUsesAgentAvatar(make(type)),
          isTrue,
          reason: '$type should use the agent avatar',
        );
      }
    });

    test('credential_stale and unknown keep the glyph chip', () {
      expect(notificationUsesAgentAvatar(make('credential_stale')), isFalse);
      expect(notificationUsesAgentAvatar(make('future_unknown_type')), isFalse);
    });

    test('avatar reads agentId / agentName / agentIconKey from metadata', () {
      final n = make('grant_pending', metadata: const {
        'agentId': 'a-1',
        'agentName': 'Acme-bot',
        'agentIconKey': 'terminal',
      });
      expect(notificationAgentId(n), 'a-1');
      expect(notificationAgentName(n), 'Acme-bot');
      expect(notificationAgentIconKey(n), 'terminal');
    });

    test('avatar degrades gracefully when metadata is missing', () {
      final n = make('agent_pending');
      expect(notificationAgentId(n), '');
      expect(notificationAgentName(n), isNull);
      expect(notificationAgentIconKey(n), isNull);
    });
  });
}
