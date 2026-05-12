import 'entry_model.dart';

/// DTO sent to `PUT /api/vaults/{vaultId}/entries/{entryId}` to update
/// an existing entry. Patch semantics — only supplied fields are updated.
class UpdateEntryRequest {
  const UpdateEntryRequest({
    required this.label,
    this.description,
    this.icon,
    required this.type,
    required this.content,
    this.urlDomain,
  });

  final String label;
  final String? description;
  final String? icon;

  /// Wire format — int ordinal of `EntryType` (`Key = 0`, `Credential = 1`).
  final int type;

  /// Re-encrypted JSONB envelope (new plaintext, same VK).
  final EntryContentModel content;

  final String? urlDomain;

  Map<String, dynamic> toJson() => {
        'label': label,
        if (description != null) 'description': description,
        'icon': icon,
        'type': type,
        'content': content.toJson(),
        if (urlDomain != null) 'urlDomain': urlDomain,
      };
}
