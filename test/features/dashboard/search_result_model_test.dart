import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/search_result_model.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';

void main() {
  test('parses authorization-scoped Agent identity', () {
    final entity = SearchResultModel.fromJson(const {
      'type': 'agent',
      'organizationId': 'o1',
      'id': 'a1',
      'name': 'Claude',
      'icon': 'bot',
    }).toEntity();
    expect(entity, isA<AgentSearchResult>());
    final agent = entity as AgentSearchResult;
    expect(agent.organizationId, 'o1');
    expect(agent.agentId, 'a1');
    expect(agent.deduplicationKey, 'agent:o1:a1');
  });

  test('parses authorization-scoped Member identity', () {
    final entity = SearchResultModel.fromJson(const {
      'type': 'member',
      'organizationId': 'o1',
      'id': 'm1',
      'name': 'Ada',
    }).toEntity();
    expect(entity, isA<MemberSearchResult>());
    expect(entity.deduplicationKey, 'member:o1:m1');
  });

  test('rejects Vault, Entry, unknown and unscoped remote hits', () {
    for (final json in <Map<String, dynamic>>[
      {'type': 'vault', 'organizationId': 'o1', 'id': 'v1', 'name': 'Vault'},
      {'type': 'entry', 'organizationId': 'o1', 'id': 'e1', 'name': 'Entry'},
      {'type': 'future', 'organizationId': 'o1', 'id': 'x1', 'name': 'Future'},
      {'type': 'agent', 'id': 'a1', 'name': 'Unscoped'},
    ]) {
      expect(() => SearchResultModel.fromJson(json), throwsFormatException);
    }
  });
}
