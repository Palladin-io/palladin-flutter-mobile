import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/audit/data/models/audit_log_model.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/audit_log_format.dart';

void main() {
  group('AuditEventType wire parsing — extended taxonomy', () {
    test('parses every new event type from its wire string', () {
      expect(
        AuditEventType.fromWire('auth.login-failed'),
        AuditEventType.loginFailed,
      );
      expect(
        AuditEventType.fromWire('apikey.created'),
        AuditEventType.apikeyCreated,
      );
      expect(
        AuditEventType.fromWire('apikey.revoked'),
        AuditEventType.apikeyRevoked,
      );
      expect(AuditEventType.fromWire('org.updated'), AuditEventType.orgUpdated);
      expect(
        AuditEventType.fromWire('user.signed-up'),
        AuditEventType.userSignedUp,
      );
      expect(
        AuditEventType.fromWire('account.recovery-completed'),
        AuditEventType.accountRecoveryCompleted,
      );
    });

    test('unrecognized wire still degrades to unknown', () {
      expect(AuditEventType.fromWire('totally.new'), AuditEventType.unknown);
      expect(AuditEventType.fromWire(42), AuditEventType.unknown);
    });

    test('known excludes unknown and covers the full catalogue', () {
      expect(AuditEventType.known, isNot(contains(AuditEventType.unknown)));
      expect(AuditEventType.known.length, AuditEventType.values.length - 1);
    });
  });

  group('AuditEventGroup mapping', () {
    test('each real event resolves to exactly one group', () {
      for (final type in AuditEventType.known) {
        expect(AuditEventType.inGroup(type.group), contains(type));
      }
    });

    test('inGroup partitions the catalogue with no overlap', () {
      final seen = <AuditEventType>{};
      for (final group in AuditEventGroup.values) {
        seen.addAll(AuditEventType.inGroup(group));
      }
      // unknown is intentionally not surfaced in any legend group list.
      expect(seen.length, AuditEventType.known.length);
    });

    test('representative members land in the expected groups', () {
      expect(
        AuditEventType.credentialAccessed.group,
        AuditEventGroup.credentialAccess,
      );
      expect(AuditEventType.grantRevoked.group, AuditEventGroup.grants);
      expect(AuditEventType.entryDeleted.group, AuditEventGroup.vaultEntry);
      expect(
        AuditEventType.agentEnrolled.group,
        AuditEventGroup.agentLifecycle,
      );
      expect(AuditEventType.apikeyCreated.group, AuditEventGroup.apiKeys);
      expect(AuditEventType.loginFailed.group, AuditEventGroup.orgAccount);
      expect(AuditEventType.userSignedUp.group, AuditEventGroup.orgAccount);
    });

    test('vault and org chip group sets are well-formed', () {
      expect(AuditEventType.vaultGroups, isNotEmpty);
      expect(AuditEventType.orgGroups, AuditEventGroup.values);
      // The vault tab never surfaces api-key or org/account chips.
      expect(
        AuditEventType.vaultGroups,
        isNot(contains(AuditEventGroup.apiKeys)),
      );
    });
  });

  group('color & icon families', () {
    test('positive/success events use the canonical green', () {
      for (final type in [
        AuditEventType.credentialAccessed,
        AuditEventType.grantCreated,
        AuditEventType.grantApproved,
        AuditEventType.agentReactivated,
        AuditEventType.apikeyActivated,
        AuditEventType.accountSetupCompleted,
        AuditEventType.accountRecoveryCompleted,
      ]) {
        expect(
          auditEventColor(type),
          AppColors.positiveAccent,
          reason: '$type',
        );
      }
    });

    test('destructive/denied events are red', () {
      for (final type in [
        AuditEventType.loginFailed,
        AuditEventType.credentialAccessDenied,
        AuditEventType.grantDenied,
        AuditEventType.grantRevoked,
        AuditEventType.agentBlocked,
        AuditEventType.agentDeleted,
        AuditEventType.vaultDeleted,
        AuditEventType.entryDeleted,
        AuditEventType.apikeyRevoked,
        AuditEventType.apikeyDeleted,
      ]) {
        expect(auditEventColor(type), AppColors.brandRed, reason: '$type');
      }
    });

    test('only an outstanding access request is peach (pending)', () {
      expect(
        auditEventColor(AuditEventType.grantRequested),
        AppColors.vaultPeach,
      );
      // Agent enrolment is NOT pending → blue, not peach.
      expect(
        auditEventColor(AuditEventType.agentEnrolled),
        AppColors.vaultBlue,
      );
    });

    test('neutral lifecycle/creation events are blue', () {
      for (final type in [
        AuditEventType.agentEnrolled,
        AuditEventType.vaultCreated,
        AuditEventType.vaultUpdated,
        AuditEventType.entryCreated,
        AuditEventType.entryUpdated,
        AuditEventType.apikeyCreated,
        AuditEventType.orgCreated,
        AuditEventType.orgUpdated,
        AuditEventType.userSignedUp,
      ]) {
        expect(auditEventColor(type), AppColors.vaultBlue, reason: '$type');
      }
    });

    test('consumed/expired/superseded/unknown are grey', () {
      expect(
        auditEventColor(AuditEventType.grantConsumed),
        AppColors.textTertiary,
      );
      expect(
        auditEventColor(AuditEventType.grantExpired),
        AppColors.textTertiary,
      );
      expect(
        auditEventColor(AuditEventType.grantSuperseded),
        AppColors.textTertiary,
      );
      expect(auditEventColor(AuditEventType.unknown), AppColors.textTertiary);
    });

    test(
      'every group has a non-null swatch and icon; lifecycle is not peach',
      () {
        for (final group in AuditEventGroup.values) {
          expect(auditGroupColor(group), isA<Color>());
          expect(auditGroupIcon(group), isA<IconData>());
        }
        // Agent lifecycle is no longer pending-peach.
        expect(
          auditGroupColor(AuditEventGroup.agentLifecycle),
          isNot(AppColors.vaultPeach),
        );
        expect(
          auditGroupColor(AuditEventGroup.agentLifecycle),
          AppColors.vaultBlue,
        );
      },
    );
  });

  group('server-denormalized name fields', () {
    test('agentName / actorName are preserved at the wire boundary', () {
      final entity = AuditLogModel.fromJson(<String, dynamic>{
        'id': 'log-9',
        'eventType': 'apikey.created',
        'actorType': 'User',
        'result': 'Succeeded',
        'actorName': 'Patryk',
        'agentId': 'a-2',
        'agentName': 'claude-code-01',
        'vaultId': 'v-9',
        'metadata': <String, String>{},
        'occurredAt': '2026-06-10T08:59:59Z',
        'createdAt': '2026-06-10T09:00:00Z',
      }).toEntity();

      expect(entity.eventType, AuditEventType.apikeyCreated);
      expect(entity.actorName, 'Patryk');
      expect(entity.agentName, 'claude-code-01');
      expect(entity.localPresentationOnly, isTrue);
    });
  });
}
