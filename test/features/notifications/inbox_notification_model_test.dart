import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/data/models/inbox_notification_model.dart';

void main() {
  test('parses an open action-required notification', () {
    final model = InboxNotificationModel.fromJson({
      'id': 'notification-1',
      'type': 'grant_pending',
      'topic': 'access',
      'title': 'Access requested',
      'body': 'An agent requested access.',
      'data': {'grantId': 'grant-1'},
      'isActionRequired': true,
      'isSecurityCritical': false,
      'isRead': false,
      'isResolved': false,
      'resolution': null,
      'actionType': 'review_grant',
      'actionTarget': '/grants/grant-1',
      'occurredAt': '2026-06-15T12:00:00Z',
    }).toEntity();

    expect(model.id, 'notification-1');
    expect(model.data['grantId'], 'grant-1');
    expect(model.isOpenAction, isTrue);
    expect(model.occurredAt.isUtc, isFalse);
  });

  test('tolerates missing optional and open-contract fields', () {
    final model = InboxNotificationModel.fromJson({
      'id': 'notification-2',
      'type': 'future_type',
      'topic': 'future-topic',
      'title': 'Future update',
      'body': 'Details',
      'occurredAt': 'invalid',
    }).toEntity();

    expect(model.data, isEmpty);
    expect(model.isActionRequired, isFalse);
    expect(model.isRead, isFalse);
    expect(model.actionType, isNull);
    expect(model.topic, 'future-topic');
  });
}
