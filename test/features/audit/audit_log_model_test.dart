import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/data/models/audit_log_model.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';

void main() {
  group('AuditLogModel.fromJson → toEntity', () {
    test('maps the complete canonical AuditLogListItem contract', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-1',
        'eventType': 'credential.accessed',
        'actorType': 2,
        'result': 1,
        'userId': null,
        'agentId': 'a-1',
        'vaultId': 'v-1',
        'entryId': 'e-1',
        'agentName': 'Claude',
        'actorName': 'Alice',
        'metadata': {'method': 'Get', 'grantType': 'Granular'},
        'occurredAt': '2026-06-01T10:04:00Z',
        'createdAt': '2026-06-01T10:05:00Z',
      }).toEntity();

      expect(entity.id, 'log-1');
      expect(entity.eventType, AuditEventType.credentialAccessed);
      expect(entity.rawEventType, 'credential.accessed');
      expect(entity.actorType, AuditActorType.agent);
      expect(entity.result, AuditResult.succeeded);
      expect(entity.agentId, 'a-1');
      expect(entity.agentName, 'Claude');
      expect(entity.actorName, 'Alice');
      expect(entity.entryId, 'e-1');
      expect(entity.entryLabel, isNull);
      expect(entity.agentReason, isNull);
      expect(entity.metadata, {'method': 'Get', 'grantType': 'Granular'});
      expect(entity.localPresentationOnly, isTrue);
      expect(
        entity.occurredAt,
        DateTime.parse('2026-06-01T10:04:00Z').toLocal(),
      );
      expect(
        entity.createdAt,
        DateTime.parse('2026-06-01T10:05:00Z').toLocal(),
      );
      expect(entity.createdAt.isUtc, isFalse); // normalized to local
    });

    test('unknown event type degrades to unknown but keeps the raw string', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-2',
        'eventType': 'future.event-type',
        'actorType': 'System',
        'result': 'Failed',
        'occurredAt': '2026-06-02T07:59:00Z',
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.eventType, AuditEventType.unknown);
      expect(entity.rawEventType, 'future.event-type');
      expect(entity.actorType, AuditActorType.system);
      expect(entity.result, AuditResult.failed);
      expect(entity.metadata, isEmpty);
    });

    test('metadata keeps only canonical string pairs', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-3',
        'eventType': 'grant.created',
        'actorType': 1,
        'result': 2,
        'metadata': <Object?, Object?>{
          'grantId': 'g-1',
          'unexpectedNumber': 7,
          42: 'not-a-string-key',
        },
        'occurredAt': '2026-06-02T08:00:00Z',
        'createdAt': '2026-06-02T08:00:01Z',
      }).toEntity();

      expect(entity.result, AuditResult.denied);
      expect(entity.metadata, {'grantId': 'g-1'});
    });

    test('actorType tolerates string and int wire forms', () {
      expect(AuditActorType.fromWire(1), AuditActorType.user);
      expect(AuditActorType.fromWire('user'), AuditActorType.user);
      expect(AuditActorType.fromWire('Agent'), AuditActorType.agent);
      expect(AuditActorType.fromWire(99), AuditActorType.unknown);
      expect(AuditResult.fromWire(1), AuditResult.succeeded);
      expect(AuditResult.fromWire('Denied'), AuditResult.denied);
      expect(AuditResult.fromWire(99), AuditResult.unknown);
    });
  });

  group('AuditEventType.entryRelevant', () {
    test('exposes the 8 existing and 8 sharing entry-scoped filter chips', () {
      expect(AuditEventType.entryRelevant.length, 16);
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
