import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/grants/data/models/grant_model.dart';
import 'package:mobile_claw_vault/features/grants/domain/entities/grant.dart';
import 'package:mobile_claw_vault/features/grants/presentation/cubit/org_grants_state.dart';

void main() {
  group('GrantModel — org-wide (/api/grants) fields', () {
    test('maps type/vaultName/capabilities/actors and consumed status', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-1',
        'vaultId': 'v-1',
        'vaultName': 'Production',
        'agentId': 'a-1',
        'agentName': 'Deploy Bot',
        'agentIconKey': 'terminal',
        'agentPublicKey': 'cHViLWtleQ==',
        'type': 'granular',
        'status': 'consumed',
        'entryId': 'e-1',
        'entryLabel': 'Gmail',
        'reason': 'send email',
        'queryLimit': 5,
        'queryCount': 5,
        'createdAt': '2026-06-01T10:00:00Z',
        'createdByName': 'Alice',
        'revokeReason': null,
        'canRevoke': false,
        'canGrantAgain': true,
      }).toEntity();

      expect(entity.status, GrantStatus.consumed);
      expect(entity.scope, GrantScope.granular);
      expect(entity.vaultName, 'Production');
      expect(entity.agentIconKey, 'terminal');
      expect(entity.agentPublicKey, 'cHViLWtleQ==');
      expect(entity.createdByName, 'Alice');
      expect(entity.canRevoke, isFalse);
      expect(entity.canGrantAgain, isTrue);
      expect(entity.status.isTerminal, isTrue);
    });

    test('capabilities default to false when the backend omits them', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-2',
        'vaultId': 'v-2',
        'agentId': 'a-2',
        'type': 'full',
        'status': 'active',
        'createdAt': '2026-06-01T10:00:00Z',
      }).toEntity();

      expect(entity.canRevoke, isFalse);
      expect(entity.canGrantAgain, isFalse);
      expect(entity.scope, GrantScope.full);
      expect(entity.status.isTerminal, isFalse);
    });
  });

  group('OrgGrantsState.filtered', () {
    Grant grant(String id, GrantStatus status, {String? agent, String? entry}) {
      return Grant(
        id: id,
        vaultId: 'v',
        agentId: 'a-$id',
        agentName: agent,
        entryLabel: entry,
        status: status,
        scope: GrantScope.granular,
        createdAt: DateTime(2026, 6, 1),
      );
    }

    final grants = [
      grant('1', GrantStatus.active, agent: 'Deploy Bot', entry: 'Gmail'),
      grant('2', GrantStatus.revoked, agent: 'CI Runner', entry: 'AWS'),
      grant('3', GrantStatus.expired, agent: 'Deploy Bot', entry: 'Slack'),
    ];

    test('status filter keeps only selected statuses', () {
      final state = OrgGrantsState(
        grants: grants,
        statusFilter: const {GrantStatus.active, GrantStatus.expired},
      );
      expect(state.filtered.map((g) => g.id), ['1', '3']);
    });

    test('empty status filter shows everything', () {
      const state = OrgGrantsState();
      expect(state.copyWith(grants: grants).filtered.length, 3);
    });

    test('search matches agent / entry / vault, case-insensitive', () {
      final state = OrgGrantsState(grants: grants, query: 'deploy');
      expect(state.filtered.map((g) => g.id), ['1', '3']);
    });

    test('counts tally per status across the full list', () {
      final state = OrgGrantsState(grants: grants);
      expect(state.counts[GrantStatus.active], 1);
      expect(state.counts[GrantStatus.revoked], 1);
      expect(state.counts[GrantStatus.expired], 1);
    });
  });
}
