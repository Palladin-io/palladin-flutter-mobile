import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_format.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  InboxNotification make(String type, Map<String, dynamic> metadata) {
    return InboxNotification(
      id: 'n',
      type: type,
      category: NotificationCategory.update,
      titleKey: type,
      metadata: metadata,
      actionState: NotificationActionState.resolved,
      occurredAt: DateTime(2026, 6, 21),
    );
  }

  group('notificationDeepLink', () {
    test('agent deep-link maps to agent detail', () {
      final n = make('agent_approved', {'actionDeepLink': '/agents/a-1'});
      expect(notificationDeepLink(n), '/agents/a-1');
    });

    test('grant deep-link collapses to its owning vault detail', () {
      final n = make('grant_approved', {
        'actionDeepLink': '/vaults/v-1/grants/g-1',
      });
      expect(notificationDeepLink(n), '/vaults/v-1');
    });

    test('entry deep-link collapses to its owning vault detail', () {
      final n = make('credential_stale', {
        'actionDeepLink': '/vaults/v-2/entries/e-1',
      });
      expect(notificationDeepLink(n), '/vaults/v-2');
    });

    test('falls back to agentId metadata when no deep-link is present', () {
      final n = make('agent_approved', {'agentId': 'a-9'});
      expect(notificationDeepLink(n), '/agents/a-9');
    });

    test('falls back to vaultId metadata when no deep-link is present', () {
      final n = make('credential_stale', {'vaultId': 'v-9'});
      expect(notificationDeepLink(n), '/vaults/v-9');
    });

    test('returns null when there is no usable target', () {
      expect(notificationDeepLink(make('future_unknown', const {})), isNull);
    });

    test('historical grant_revoked renders without crashing and has no target',
        () {
      // Backend no longer emits grant_revoked, but a historical item must still
      // resolve gracefully (no inline actions, deep-links to its vault).
      final n = make('grant_revoked', {
        'actionDeepLink': '/vaults/v-3/grants/g-3',
      });
      expect(notificationDeepLink(n), '/vaults/v-3');
    });

    test('unknown deep-link prefix is ignored, falls through to metadata', () {
      final n = make('grant_approved', {
        'actionDeepLink': '/settings/something',
        'agentId': 'a-5',
      });
      expect(notificationDeepLink(n), '/agents/a-5');
    });
  });

  group('notificationViewTarget (contextual View label)', () {
    test('agent deep-link → agent target → "View Agent"', () {
      final n = make('agent_approved', {'actionDeepLink': '/agents/a-1'});
      expect(notificationViewTarget(n), NotificationViewTarget.agent);
      expect(
        notificationViewLabel(l10n, notificationViewTarget(n)!),
        l10n.inboxViewAgent,
      );
    });

    test('grant deep-link → access target → "View Access"', () {
      final n = make('grant_approved', {
        'actionDeepLink': '/vaults/v-1/grants/g-1',
      });
      expect(notificationViewTarget(n), NotificationViewTarget.access);
      expect(
        notificationViewLabel(l10n, notificationViewTarget(n)!),
        l10n.inboxViewAccess,
      );
    });

    test('entry deep-link → entry target → "View Entry"', () {
      final n = make('credential_stale', {
        'actionDeepLink': '/vaults/v-1/entries/e-1',
      });
      expect(notificationViewTarget(n), NotificationViewTarget.entry);
      expect(
        notificationViewLabel(l10n, notificationViewTarget(n)!),
        l10n.inboxViewEntry,
      );
    });

    test('bare vault deep-link → access target (grant context)', () {
      final n = make('grant_denied', {'actionDeepLink': '/vaults/v-1'});
      expect(notificationViewTarget(n), NotificationViewTarget.access);
    });

    test('falls back to notification type when no deep-link present', () {
      expect(
        notificationViewTarget(make('agent_approved', const {})),
        NotificationViewTarget.agent,
      );
      expect(
        notificationViewTarget(make('grant_revoked', const {})),
        NotificationViewTarget.access,
      );
      expect(
        notificationViewTarget(make('credential_stale', const {})),
        NotificationViewTarget.entry,
      );
    });

    test('unknown type with no deep-link has no view target', () {
      expect(notificationViewTarget(make('future_unknown', const {})), isNull);
    });
  });
}
