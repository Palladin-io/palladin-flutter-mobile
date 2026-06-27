import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/audit/domain/entities/audit_log_entry.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/entry_logs_state.dart';

AuditLogEntry _entry({
  required String id,
  AuditEventType type = AuditEventType.credentialAccessed,
  String? agentId,
  DateTime? at,
}) {
  return AuditLogEntry(
    id: id,
    eventType: type,
    rawEventType: type.wire,
    actorType: AuditActorType.agent,
    createdAt: at ?? DateTime(2026, 6, 1, 10),
    agentId: agentId,
    entryId: 'e-1',
  );
}

void main() {
  group('EntryLogsState.filtered', () {
    final entries = [
      _entry(
        id: '1',
        type: AuditEventType.credentialAccessed,
        agentId: 'a-1',
        at: DateTime(2026, 6, 1, 10),
      ),
      _entry(
        id: '2',
        type: AuditEventType.grantCreated,
        agentId: 'a-2',
        at: DateTime(2026, 6, 5, 12),
      ),
      _entry(
        id: '3',
        type: AuditEventType.credentialAccessDenied,
        agentId: 'a-1',
        at: DateTime(2026, 6, 10, 9),
      ),
    ];

    test('no filters returns every entry', () {
      final state = EntryLogsState(entries: entries);
      expect(state.filtered.map((e) => e.id), ['1', '2', '3']);
      expect(state.hasActiveFilters, isFalse);
    });

    test('event-type filter narrows to selected types', () {
      final state = EntryLogsState(
        entries: entries,
        eventTypeFilter: const {AuditEventType.credentialAccessDenied},
      );
      expect(state.filtered.map((e) => e.id), ['3']);
      expect(state.hasActiveFilters, isTrue);
    });

    test('agent filter narrows to the selected agent', () {
      final state = EntryLogsState(entries: entries, agentFilter: 'a-1');
      expect(state.filtered.map((e) => e.id), ['1', '3']);
    });

    test('date range bounds are inclusive of the window', () {
      final state = EntryLogsState(
        entries: entries,
        fromDate: DateTime(2026, 6, 4),
        toDate: DateTime(2026, 6, 6),
      );
      expect(state.filtered.map((e) => e.id), ['2']);
    });

    test('search matches resolved agent name', () {
      final state = EntryLogsState(
        entries: entries,
        agentNames: const {'a-2': 'Deploy Bot'},
        query: 'deploy',
      );
      expect(state.filtered.map((e) => e.id), ['2']);
    });

    test('agentOptions are distinct and sorted by resolved name', () {
      final state = EntryLogsState(
        entries: entries,
        agentNames: const {'a-1': 'Zeta', 'a-2': 'Alpha'},
      );
      expect(state.agentOptions.map((o) => o.name), ['Alpha', 'Zeta']);
    });
  });
}
