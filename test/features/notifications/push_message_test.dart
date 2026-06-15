import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/notifications/domain/entities/push_message.dart';

void main() {
  group('PushNotificationType.fromRaw', () {
    test('maps known backend type strings', () {
      expect(
        PushNotificationType.fromRaw('grant_pending'),
        PushNotificationType.grantPending,
      );
      expect(
        PushNotificationType.fromRaw('grant_approved'),
        PushNotificationType.grantApproved,
      );
      expect(
        PushNotificationType.fromRaw('agent_pending'),
        PushNotificationType.agentPending,
      );
    });

    test('falls back to unknown for null / unrecognized', () {
      expect(PushNotificationType.fromRaw(null), PushNotificationType.unknown);
      expect(
        PushNotificationType.fromRaw('something_new'),
        PushNotificationType.unknown,
      );
    });
  });

  group('PushMessage.fromData', () {
    test('parses type and ids', () {
      final message = PushMessage.fromData(
        <String, dynamic>{
          'type': 'grant_pending',
          'notificationId': 'n-1',
          'grantId': 'g-1',
          'agentId': 'a-1',
          'entryId': 'e-1',
        },
        title: 'New grant',
        body: 'Agent wants access',
      );

      expect(message.type, PushNotificationType.grantPending);
      expect(message.notificationId, 'n-1');
      expect(message.grantId, 'g-1');
      expect(message.agentId, 'a-1');
      expect(message.entryId, 'e-1');
      expect(message.title, 'New grant');
      expect(message.body, 'Agent wants access');
    });

    test('toRoutingData round-trips the notification id', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'type': 'grant_pending',
        'notificationId': 'n-1',
        'grantId': 'g-1',
      });
      final round = PushMessage.fromData(message.toRoutingData());

      expect(round.notificationId, 'n-1');
      expect(round.grantId, 'g-1');
      expect(round.type, PushNotificationType.grantPending);
    });

    test('treats empty-string ids as null', () {
      final message = PushMessage.fromData(<String, dynamic>{
        'type': 'agent_pending',
        'agentId': '',
      });

      expect(message.type, PushNotificationType.agentPending);
      expect(message.agentId, isNull);
    });

    test('never throws on a malformed / empty payload', () {
      final message = PushMessage.fromData(const <String, dynamic>{});
      expect(message.type, PushNotificationType.unknown);
      expect(message.grantId, isNull);
      expect(message.agentId, isNull);
    });
  });
}
