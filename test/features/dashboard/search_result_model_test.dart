import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/search_result_model.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';

void main() {
  test('parses authorization-scoped Agent identity', () {
    final entity = SearchResultModel.fromJson(const {
      'type': 'agent',
      'id': 'a1',
      'name': 'Claude',
    }).toEntity();
    expect(entity, isA<AgentSearchResult>());
    final agent = entity as AgentSearchResult;
    expect(agent.agentId, 'a1');
    expect(agent.deduplicationKey, 'agent:a1');
  });

  test('parses authorization-scoped Member identity', () {
    final entity = SearchResultModel.fromJson(const {
      'type': 'member',
      'id': 'm1',
      'name': 'Ada',
    }).toEntity();
    expect(entity, isA<MemberSearchResult>());
    expect(entity.deduplicationKey, 'member:m1');
  });

  test('preserves future remote types without known navigation scope', () {
    for (final json in <Map<String, dynamic>>[
      {'type': 'vault', 'id': 'v1', 'name': 'Vault'},
      {'type': 'entry', 'id': 'e1', 'name': 'Entry'},
      {'type': 'future', 'id': 'x1', 'name': 'Future'},
    ]) {
      final result = SearchResultModel.fromJson(json).toEntity();
      expect(result, isA<UnknownSearchResult>());
      expect(result.id, json['id']);
    }
  });
}
