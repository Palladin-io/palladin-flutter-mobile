import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/data/models/inbox_notification_model.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/inbox_notification.dart';

void main() {
  test('parses an open action-required notification', () {
    final model = InboxNotificationModel.fromJson({
      'id': 'notification-1',
      'type': 'grant_pending',
      'category': 'ActionRequired',
      'titleKey': 'grant_pending',
      'metadata': {'grantId': 'grant-1', 'agentName': 'Acme-bot'},
      'actionState': 'Pending',
      'occurredAt': '2026-06-15T12:00:00Z',
    }).toEntity();

    expect(model.id, 'notification-1');
    expect(model.grantId, 'grant-1');
    expect(model.metadata['agentName'], 'Acme-bot');
    expect(model.category, NotificationCategory.actionRequired);
    expect(model.actionState, NotificationActionState.pending);
    expect(model.isOpenAction, isTrue);
    expect(model.isRead, isFalse);
    expect(model.occurredAt.isUtc, isFalse);
  });

  test('resolved action-required item is not an open action', () {
    final model = InboxNotificationModel.fromJson({
      'id': 'notification-3',
      'type': 'grant_revoked',
      'category': 'ActionRequired',
      'titleKey': 'grant_revoked',
      'metadata': {'agentName': 'old-bot'},
      'actionState': 'Resolved',
      'occurredAt': '2026-06-15T12:00:00Z',
      'readAt': '2026-06-15T12:30:00Z',
    }).toEntity();

    expect(model.isOpenAction, isFalse);
    expect(model.isRead, isTrue);
  });

  test('tolerates missing optional and open-contract fields', () {
    final model = InboxNotificationModel.fromJson({
      'id': 'notification-2',
      'type': 'future_type',
      'occurredAt': 'invalid',
    }).toEntity();

    expect(model.metadata, isEmpty);
    expect(model.category, NotificationCategory.update);
    expect(model.actionState, NotificationActionState.none);
    expect(model.isRead, isFalse);
    expect(model.isOpenAction, isFalse);
  });
}
