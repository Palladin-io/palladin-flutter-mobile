import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/audit_log_state.dart';

AuditLogEntry _entry(
  String id, {
  required AuditEventType type,
  AuditActorType actorType = AuditActorType.agent,
  String? agentId,
  String? agentName,
  String? userId,
  String? actorName,
  String? vaultId,
  String? entryLabel,
  DateTime? at,
  DateTime? occurredAt,
}) {
  return AuditLogEntry(
    id: id,
    eventType: type,
    rawEventType: type.wire,
    actorType: actorType,
    createdAt: at ?? DateTime(2026, 6, 1, 10),
    occurredAt: occurredAt,
    agentId: agentId,
    agentName: agentName,
    userId: userId,
    actorName: actorName,
    vaultId: vaultId,
    entryLabel: entryLabel,
  );
}

void main() {
  final entries = [
    _entry(
      '1',
      type: AuditEventType.credentialAccessed,
      agentId: 'a-1',
      agentName: 'claude',
      vaultId: 'v-1',
      at: DateTime(2026, 6, 1),
    ),
    _entry(
      '2',
      type: AuditEventType.grantRevoked,
      agentId: 'a-2',
      agentName: 'cursor',
      vaultId: 'v-2',
      entryLabel: 'Stripe Key',
      at: DateTime(2026, 6, 5),
    ),
    _entry(
      '3',
      type: AuditEventType.entryCreated,
      actorType: AuditActorType.user,
      userId: 'u-1',
      actorName: 'Patryk',
      vaultId: 'v-1',
      at: DateTime(2026, 6, 10),
    ),
  ];

  AuditLogState base() => AuditLogState(
    scope: AuditLogScope.org,
    status: AuditLogStatus.loaded,
    entries: entries,
  );

  group('filtered', () {
    test('no filters returns everything', () {
      expect(base().filtered.length, 3);
    });

    test('group filter keeps only matching event groups', () {
      final s = base().copyWith(groupFilters: {AuditEventGroup.grants});
      expect(s.filtered.map((e) => e.id), ['2']);
    });

    test('multi-group filter is a union', () {
      final s = base().copyWith(
        groupFilters: {AuditEventGroup.grants, AuditEventGroup.vaultEntry},
      );
      expect(s.filtered.map((e) => e.id), ['2', '3']);
    });

    test('agent filter narrows by agent id', () {
      final s = base().copyWith(agentFilters: {'a-1'});
      expect(s.filtered.map((e) => e.id), ['1']);
    });

    test('multi-select agent filter is a union (OR within the facet)', () {
      final s = base().copyWith(agentFilters: {'a-1', 'a-2'});
      expect(s.filtered.map((e) => e.id), ['1', '2']);
    });

    test('user filter narrows by actor user id', () {
      final s = base().copyWith(userFilters: {'u-1'});
      expect(s.filtered.map((e) => e.id), ['3']);
    });

    test('vault filter narrows by vault id', () {
      final s = base().copyWith(vaultFilters: {'v-2'});
      expect(s.filtered.map((e) => e.id), ['2']);
    });

    test('multi-select vault filter is a union', () {
      final s = base().copyWith(vaultFilters: {'v-1', 'v-2'});
      expect(s.filtered.map((e) => e.id), ['1', '2', '3']);
    });

    test('date range is inclusive of both bounds', () {
      final s = base().copyWith(
        fromDate: DateTime(2026, 6, 5),
        toDate: DateTime(2026, 6, 10, 23, 59, 59),
      );
      expect(s.filtered.map((e) => e.id), ['2', '3']);
    });

    test('date range uses source occurredAt, not persistence createdAt', () {
      final occurred = DateTime(2026, 6, 5);
      final persisted = DateTime(2026, 6, 20);
      final state = base().copyWith(
        entries: [
          _entry(
            'delayed',
            type: AuditEventType.entryCreated,
            at: persisted,
            occurredAt: occurred,
          ),
        ],
        fromDate: DateTime(2026, 6, 4),
        toDate: DateTime(2026, 6, 6),
      );

      expect(state.filtered.map((entry) => entry.id), ['delayed']);
    });

    test('query matches entry label, agent name and actor name', () {
      expect(base().copyWith(query: 'stripe').filtered.map((e) => e.id), ['2']);
      expect(base().copyWith(query: 'cursor').filtered.map((e) => e.id), ['2']);
      expect(base().copyWith(query: 'patryk').filtered.map((e) => e.id), ['3']);
    });

    test('combined facets AND together', () {
      final s = base().copyWith(
        groupFilters: {AuditEventGroup.vaultEntry},
        userFilters: {'u-1'},
      );
      expect(s.filtered.map((e) => e.id), ['3']);
    });
  });

  group('option lists', () {
    test('agentOptions are distinct and sorted by name', () {
      final opts = base().agentOptions;
      expect(opts.map((o) => o.id), ['a-1', 'a-2']);
      expect(opts.map((o) => o.name), ['claude', 'cursor']);
    });

    test('userOptions surface distinct user actors by name', () {
      final opts = base().userOptions;
      expect(opts.map((o) => o.id), ['u-1']);
      expect(opts.single.name, 'Patryk');
    });

    test('userOptions leave name null when no actorName is known', () {
      final s = base().copyWith(
        entries: [
          _entry(
            'x',
            type: AuditEventType.vaultUpdated,
            actorType: AuditActorType.user,
            userId: 'u-9',
          ),
        ],
      );
      final opt = s.userOptions.single;
      expect(opt.id, 'u-9');
      // Presentation substitutes a localized "Unknown user" — never a raw id.
      expect(opt.name, isNull);
    });

    test('vaultOptions fall back to a shortened id without a name', () {
      final s = base().copyWith(vaultNames: {'v-1': 'Production'});
      final opts = s.vaultOptions;
      expect(opts.firstWhere((o) => o.id == 'v-1').name, 'Production');
      // v-2 has no resolved name and is short → shown verbatim.
      expect(opts.firstWhere((o) => o.id == 'v-2').name, 'v-2');
    });
  });

  group('filter flags', () {
    test(
      'hasActiveFilters is true for any sheet facet, false when all empty',
      () {
        expect(base().hasActiveFilters, isFalse);
        expect(
          base()
              .copyWith(groupFilters: {AuditEventGroup.grants})
              .hasActiveFilters,
          isTrue,
        );
        expect(base().copyWith(userFilters: {'u-1'}).hasActiveFilters, isTrue);
        expect(base().copyWith(agentFilters: {'a-1'}).hasActiveFilters, isTrue);
        expect(base().copyWith(vaultFilters: {'v-1'}).hasActiveFilters, isTrue);
      },
    );

    test('an empty set clears a facet', () {
      final s = base().copyWith(
        agentFilters: {'a-1'},
        userFilters: {'u-1'},
        groupFilters: {AuditEventGroup.grants},
      );
      final cleared = s.copyWith(
        agentFilters: {},
        userFilters: {},
        groupFilters: {},
      );
      expect(cleared.agentFilters, isEmpty);
      expect(cleared.userFilters, isEmpty);
      expect(cleared.groupFilters, isEmpty);
      expect(cleared.hasActiveFilters, isFalse);
    });
  });
}
