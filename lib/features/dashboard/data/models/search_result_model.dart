import '../../domain/entities/search_result_entity.dart';

/// Strict DTO for one authorization-scoped administrative search hit.
sealed class SearchResultModel {
  const SearchResultModel();

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('Malformed administrative search hit');
    }
    return switch (type) {
      'agent' => AgentSearchResultModel(agentId: id, name: name),
      'member' => MemberSearchResultModel(memberId: id, name: name),
      _ => throw const FormatException('Unsupported remote search hit type'),
    };
  }

  SearchResultEntity toEntity();
}

final class AgentSearchResultModel extends SearchResultModel {
  const AgentSearchResultModel({required this.agentId, required this.name});
  final String agentId;
  final String name;

  @override
  AgentSearchResult toEntity() =>
      AgentSearchResult(agentId: agentId, displayName: name);
}

final class MemberSearchResultModel extends SearchResultModel {
  const MemberSearchResultModel({required this.memberId, required this.name});
  final String memberId;
  final String name;

  @override
  MemberSearchResult toEntity() =>
      MemberSearchResult(memberId: memberId, displayName: name);
}
