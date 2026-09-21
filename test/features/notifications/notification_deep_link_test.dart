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
    for (final type in [
      'grant_pending',
      'grant_approved',
      'grant_denied',
      'grant_revoked',
    ]) {
      test('$type for an Entry does not open the Entries list', () {
        final n = make(type, {
          'vaultId': 'v-1',
          'entryId': 'e-1',
          'grantType': 'granular',
        });
        expect(
          notificationDeepLink(n),
          isA<NotificationEntryDestination>()
              .having((target) => target.vaultId, 'vaultId', 'v-1')
              .having((target) => target.entryId, 'entryId', 'e-1'),
        );
      });
    }
    test('agent deep-link maps to agent detail', () {
      final n = make('agent_approved', {
        'agentId': 'a-1',
        'actionDeepLink': '/agents/forged',
      });
      expect(
        notificationDeepLink(n),
        isA<NotificationRouteDestination>().having(
          (target) => target.route,
          'route',
          '/agents/a-1',
        ),
      );
    });

    test('FULL access opens its owning vault detail', () {
      final n = make('grant_approved', {
        'vaultId': 'v-1',
        'grantType': 'full',
        'entryId': 'e-ignored',
        'actionDeepLink': '/vaults/v-1/grants/g-1',
      });
      expect(
        notificationDeepLink(n),
        isA<NotificationRouteDestination>().having(
          (target) => target.route,
          'route',
          '/vaults/v-1',
        ),
      );
    });

    test('stale credential opens the exact Entry from metadata', () {
      final n = make('credential_stale', {
        'vaultId': 'v-2',
        'entryId': 'e-1',
        'actionDeepLink': '/vaults/forged/entries/forged',
      });
      expect(
        notificationDeepLink(n),
        isA<NotificationEntryDestination>()
            .having((target) => target.vaultId, 'vaultId', 'v-2')
            .having((target) => target.entryId, 'entryId', 'e-1'),
      );
    });

    test('falls back to agentId metadata when no deep-link is present', () {
      final n = make('agent_approved', {'agentId': 'a-9'});
      expect(
        notificationDeepLink(n),
        isA<NotificationRouteDestination>().having(
          (target) => target.route,
          'route',
          '/agents/a-9',
        ),
      );
    });

    test('missing Entry does not fall back to the Entries list', () {
      final n = make('credential_stale', {'vaultId': 'v-9'});
      expect(notificationDeepLink(n), isNull);
    });

    test('returns null when there is no usable target', () {
      expect(notificationDeepLink(make('future_unknown', const {})), isNull);
    });

    test('historical FULL grant_revoked opens its Vault', () {
      final n = make('grant_revoked', {
        'vaultId': 'v-3',
        'grantType': 'full',
        'actionDeepLink': '/vaults/v-3/grants/g-3',
      });
      expect(
        notificationDeepLink(n),
        isA<NotificationRouteDestination>().having(
          (target) => target.route,
          'route',
          '/vaults/v-3',
        ),
      );
    });

    test('deep-link cannot widen an allowlisted type destination', () {
      final n = make('grant_approved', {
        'actionDeepLink': '/settings/something',
        'agentId': 'a-5',
      });
      expect(notificationDeepLink(n), isNull);
    });

    for (final scope in ['granular', 'scriptExecution', 1, 3]) {
      test('$scope requires the exact Entry and Vault', () {
        expect(
          notificationDeepLink(
            make('grant_approved', {'grantType': scope, 'vaultId': 'v'}),
          ),
          isNull,
        );
        expect(
          notificationDeepLink(
            make('grant_approved', {'grantType': scope, 'entryId': 'e'}),
          ),
          isNull,
        );
        expect(
          notificationDeepLink(
            make('grant_approved', {
              'grantType': scope,
              'vaultId': 'v',
              'entryId': 'e',
            }),
          ),
          isA<NotificationEntryDestination>()
              .having((target) => target.vaultId, 'vaultId', 'v')
              .having((target) => target.entryId, 'entryId', 'e'),
        );
      });
    }

    test('does not infer grant type from nullable Entry id', () {
      for (final scope in [null, 'future']) {
        expect(
          notificationDeepLink(
            make('grant_approved', {
              'vaultId': 'v',
              'entryId': 'e',
              'grantType': scope,
            }),
          ),
          isNull,
        );
      }
    });
  });

  group('notificationViewTarget (contextual View label)', () {
    test('agent deep-link → agent target → "View Agent"', () {
      final n = make('agent_approved', {
        'agentId': 'a-1',
        'actionDeepLink': '/agents/forged',
      });
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
