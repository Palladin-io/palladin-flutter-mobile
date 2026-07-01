import '../../domain/entities/search_result_entity.dart';

/// DTO for one item in the `GET /api/search` response.
///
/// Parses `{ "type", "id", "name", "vaultName"?, "icon"? }`. The backend
/// emits `type` as one of `"agent" | "vault" | "entry"`; unknown values
/// fall back to [SearchResultType.entry] so a forward-compatible backend
/// change never crashes the client.
class SearchResultModel {
  const SearchResultModel({
    required this.type,
    required this.id,
    required this.name,
    this.vaultName,
    this.icon,
  });

  final SearchResultType type;
  final String id;
  final String name;
  final String? vaultName;
  final String? icon;

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      type: _parseType(json['type'] as String?),
      id: json['id'] as String,
      name: json['name'] as String,
      vaultName: json['vaultName'] as String?,
      icon: json['icon'] as String?,
    );
  }

  static SearchResultType _parseType(String? raw) {
    return switch (raw) {
      'agent' => SearchResultType.agent,
      'vault' => SearchResultType.vault,
      'entry' => SearchResultType.entry,
      _ => SearchResultType.entry,
    };
  }

  SearchResultEntity toEntity() => SearchResultEntity(
        type: type,
        id: id,
        name: name,
        vaultName: vaultName,
        icon: icon,
      );
}
