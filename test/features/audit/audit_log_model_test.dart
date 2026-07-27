import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/data/models/audit_log_model.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';

void main() {
  group('AuditLogModel.fromJson → toEntity', () {
    test('keeps structural fields and discards hostile presentation data', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-1',
        'eventType': 'credential.accessed',
        'actorType': 2,
        'userId': null,
        'agentId': 'a-1',
        'vaultId': 'v-1',
        'entryId': 'e-1',
        'entryLabel': 'Stripe API Key',
        'agentReason': null,
        'metadata': {'method': 'Get', 'grantType': 'Granular'},
        'createdAt': '2026-06-01T10:05:00Z',
      }).toEntity();

      expect(entity.id, 'log-1');
      expect(entity.eventType, AuditEventType.credentialAccessed);
      expect(entity.rawEventType, 'credential.accessed');
      expect(entity.actorType, AuditActorType.agent);
      expect(entity.agentId, 'a-1');
      expect(entity.entryId, 'e-1');
      expect(entity.entryLabel, isNull);
      expect(entity.agentReason, isNull);
      expect(entity.metadata, isEmpty);
      expect(entity.localPresentationOnly, isTrue);
      expect(entity.createdAt.isUtc, isFalse); // normalized to local
    });

    test('unknown event type degrades to unknown but keeps the raw string', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-2',
        'eventType': 'future.event-type',
        'actorType': 'System',
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.eventType, AuditEventType.unknown);
      expect(entity.rawEventType, 'future.event-type');
      expect(entity.actorType, AuditActorType.system);
      expect(entity.metadata, isEmpty);
    });

    test('actorType tolerates string and int wire forms', () {
      expect(AuditActorType.fromWire(1), AuditActorType.user);
      expect(AuditActorType.fromWire('user'), AuditActorType.user);
      expect(AuditActorType.fromWire('Agent'), AuditActorType.agent);
      expect(AuditActorType.fromWire(99), AuditActorType.system);
    });
  });

  group('AuditEventType.entryRelevant', () {
    test('exposes exactly the 8 entry-scoped filter chips', () {
      expect(AuditEventType.entryRelevant.length, 8);
      expect(
        AuditEventType.entryRelevant,
        containsAll([
          AuditEventType.credentialAccessed,
          AuditEventType.credentialAccessDenied,
          AuditEventType.entryCreated,
          AuditEventType.entryUpdated,
          AuditEventType.entryDeleted,
          AuditEventType.grantCreated,
          AuditEventType.grantApproved,
          AuditEventType.grantRevoked,
        ]),
      );
    });
  });
}
