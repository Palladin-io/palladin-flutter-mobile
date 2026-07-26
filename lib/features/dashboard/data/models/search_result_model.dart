import '../../domain/entities/search_result_entity.dart';

/// Strict DTO for one authorization-scoped administrative search hit.
sealed class SearchResultModel {
  const SearchResultModel();

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    final organizationId = json['organizationId'];
    final id = json['id'];
    final name = json['name'];
    final icon = json['icon'];
    if (organizationId is! String ||
        organizationId.isEmpty ||
        id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        (icon != null && icon is! String)) {
      throw const FormatException('Malformed administrative search hit');
    }
    return switch (type) {
      'agent' => AgentSearchResultModel(
        organizationId: organizationId,
        agentId: id,
        name: name,
        icon: icon as String?,
      ),
      'member' => MemberSearchResultModel(
        organizationId: organizationId,
        memberId: id,
        name: name,
        icon: icon as String?,
      ),
      _ => throw const FormatException('Unsupported remote search hit type'),
    };
  }

  SearchResultEntity toEntity();
}

final class AgentSearchResultModel extends SearchResultModel {
  const AgentSearchResultModel({
    required this.organizationId,
    required this.agentId,
    required this.name,
    this.icon,
  });
  final String organizationId;
  final String agentId;
  final String name;
  final String? icon;

  @override
  AgentSearchResult toEntity() => AgentSearchResult(
    organizationId: organizationId,
    agentId: agentId,
    displayName: name,
    iconReference: icon,
  );
}

final class MemberSearchResultModel extends SearchResultModel {
  const MemberSearchResultModel({
    required this.organizationId,
    required this.memberId,
    required this.name,
    this.icon,
  });
  final String organizationId;
  final String memberId;
  final String name;
  final String? icon;

  @override
  MemberSearchResult toEntity() => MemberSearchResult(
    organizationId: organizationId,
    memberId: memberId,
    displayName: name,
    iconReference: icon,
  );
}
