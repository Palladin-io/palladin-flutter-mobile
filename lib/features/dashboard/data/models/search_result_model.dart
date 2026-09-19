import '../../domain/entities/search_result_entity.dart';

/// Typed DTO for one authorization-scoped administrative search hit.
sealed class SearchResultModel {
  const SearchResultModel();

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final id = json['id'] as String;
    final name = json['name'] as String;
    return switch (type) {
      'agent' => AgentSearchResultModel(agentId: id, name: name),
      'member' => MemberSearchResultModel(memberId: id, name: name),
      _ => UnknownSearchResultModel(rawType: type, id: id, name: name),
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

/// Future server types stay visible without acquiring navigation capabilities.
final class UnknownSearchResultModel extends SearchResultModel {
  const UnknownSearchResultModel({
    required this.rawType,
    required this.id,
    required this.name,
  });
  final String rawType;
  final String id;
  final String name;
  @override
  UnknownSearchResult toEntity() =>
      UnknownSearchResult(rawType: rawType, id: id, name: name);
}
