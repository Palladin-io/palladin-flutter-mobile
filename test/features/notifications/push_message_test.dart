import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/push_message.dart';

void main() {
  group('PushNotificationType.fromRaw', () {
    test('maps known values and rejects future values safely', () {
      expect(
        PushNotificationType.fromRaw('grant_pending'),
        PushNotificationType.grantPending,
      );
      expect(
        PushNotificationType.fromRaw('credential_stale'),
        PushNotificationType.credentialStale,
      );
      expect(
        PushNotificationType.fromRaw('future_type'),
        PushNotificationType.unknown,
      );
    });
  });

  group('PushMessage structural contract', () {
    const raw = <String, dynamic>{
      'type': 'grant_pending',
      'category': 'actionRequired',
      'subjectId': '11111111-1111-4111-8111-111111111111',
      'occurredAt': '2026-07-26T20:00:00Z',
    };

    test('parses and round-trips only the frozen generic fields', () {
      final message = PushMessage.fromData(raw);

      expect(message, isNotNull);
      expect(message!.subjectId, raw['subjectId']);
      expect(message.category, 'actionRequired');
      expect(message.toRoutingData().keys.toSet(), {
        'type',
        'category',
        'subjectId',
        'occurredAt',
      });
      expect(
        PushMessage.fromData(message.toRoutingData())!.subjectId,
        message.subjectId,
      );
    });

    test('fails closed for malformed or incomplete payloads', () {
      for (final key in raw.keys) {
        final malformed = Map<String, dynamic>.from(raw)..remove(key);
        expect(PushMessage.fromData(malformed), isNull, reason: key);
      }
      expect(PushMessage.fromData({...raw, 'category': 'future'})?.category, 'future');
      expect(
        PushMessage.fromData({...raw, 'occurredAt': 'not-an-instant'}),
        isNull,
      );
      expect(PushMessage.fromData({...raw, 'vaultId': 'forged'}), isNull);
    });
  });
}
