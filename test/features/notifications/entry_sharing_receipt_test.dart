import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_format.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Index extends Mock implements MemberIndexReader {}

void main() {
  test(
    'receipt labels resolve only from the active local index and redact on lock',
    () async {
      final index = _Index();
      when(() => index.waitForCurrent('vault')).thenAnswer((_) async {});
      when(() => index.entries('vault')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'entry',
          entryType: 1,
          memberLabel: 'Local entry',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
      ]);
      final resolver = NotificationPresentationResolver(index: index);
      final source = InboxNotification(
        id: 'receipt',
        type: 'entry_share_received',
        category: NotificationCategory.update,
        titleKey: '',
        actionState: NotificationActionState.none,
        metadata: const {
          'vaultId': 'vault',
          'entryId': 'entry',
          'shareId': 'share',
          'entryLabel': 'Forged label',
          'vaultName': 'Forged vault',
          'actorName': 'Forged actor',
          'actionDeepLink': 'https://untrusted.invalid',
        },
        occurredAt: DateTime(2026, 9, 21),
      );
      final vault = VaultEntity(
        id: 'vault',
        name: 'Local vault',
        grantMode: GrantMode.granular,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        entryCount: 1,
        activeGrantCount: 0,
        memberCount: 1,
      );
      final resolved = await resolver.resolve(
        items: [source],
        unlocked: true,
        activeAccountId: 'account',
        activeOrganizationId: 'org',
        activeVaults: [vault],
      );
      expect(resolved.single.metadata['entryLabel'], 'Local entry');
      expect(resolved.single.metadata['vaultName'], 'Local vault');
      expect(resolved.single.metadata['actorName'], isNull);
      expect(resolved.single.metadata['actionDeepLink'], isNull);
      final redacted = resolver.redact(resolved).single;
      expect(redacted.metadata['entryLabel'], isNull);
      expect(redacted.metadata['vaultName'], isNull);
      expect(redacted.metadata['vaultId'], isNull);
      expect(redacted.metadata['entryId'], isNull);
      expect(redacted.metadata['shareId'], 'share');
      final inaccessible = await resolver.resolve(
        items: [source],
        unlocked: true,
        activeAccountId: 'other-account',
        activeOrganizationId: 'other-org',
        activeVaults: const [],
      );
      expect(inaccessible.single.metadata['entryLabel'], isNull);
      expect(inaccessible.single.metadata['vaultId'], isNull);
      verify(() => index.waitForCurrent('vault')).called(1);
    },
  );
  final receipt = InboxNotification(
    id: 'receipt',
    type: 'entry_share_received',
    category: NotificationCategory.update,
    actionState: NotificationActionState.none,
    titleKey: 'notification.entry_share_received.title',
    metadata: const {
      'shareId': '00112233-4455-4677-8899-aabbccddeeff',
      'entryLabel': 'Local entry',
      'vaultName': 'Local vault',
      'actorName': 'Must not appear',
      'agentName': 'Must not appear',
    },
    occurredAt: DateTime(2026, 9, 21),
  );
  for (final locale in ['en', 'pl']) {
    test(
      'sharing receipt has localized display-only presentation in $locale',
      () {
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(notificationFilterTypes, contains(receipt.type));
        expect(
          notificationTitle(l10n, receipt),
          locale == 'en'
              ? 'Shared copy received'
              : 'Odebrano udostępnioną kopię',
        );
        expect(notificationSubtitle(l10n, receipt), isNotEmpty);
        final rows = notificationRows(l10n, receipt);
        expect(rows, hasLength(3));
        expect(rows.first.value, 'Local entry · Local vault');
        expect(rows[1].value, '00112233…ddeeff');
        expect(
          rows.last.value,
          locale == 'en'
              ? 'Display confirmed — not proof of reading.'
              : 'Potwierdzono wyświetlenie — nie przeczytanie.',
        );
        expect(
          rows.map((row) => row.value),
          isNot(contains('Must not appear')),
        );
        expect(notificationIcon(receipt), Icons.check_circle_outline);
        expect(notificationGlyphTint(receipt), AppColors.positiveAccent);
        expect(notificationUsesAgentAvatar(receipt), false);
        expect(receipt.isOpenAction, false);
        expect(receipt.isCollapsedPending, false);
      },
    );
  }
}
