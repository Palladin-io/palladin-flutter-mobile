import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('decision actions match View access geometry and text', (
    tester,
  ) async {
    final item = InboxNotification(
      id: 'demo',
      type: 'grant_pending',
      category: NotificationCategory.actionRequired,
      titleKey: '',
      metadata: const {},
      actionState: NotificationActionState.pending,
      occurredAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 350,
              child: Column(
                children: [
                  NotificationCard(
                    item: item,
                    onTap: () {},
                    onPrimary: () {},
                    onSecondary: () {},
                    primaryLabel: 'Accept',
                    secondaryLabel: 'Deny',
                  ),
                  NotificationCard(
                    item: item,
                    onTap: () {},
                    onView: () {},
                    viewLabel: 'View access',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final reference = find.widgetWithText(TextButton, 'View access');
    final style = tester.widget<Text>(find.text('View access')).style;
    for (final label in ['Accept', 'Deny']) {
      expect(
        tester.getSize(find.widgetWithText(TextButton, label)).height,
        tester.getSize(reference).height,
      );
      expect(tester.widget<Text>(find.text(label)).style, style);
    }
    expect(tester.takeException(), isNull);
  });
}
