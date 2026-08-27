import '../../domain/entities/custom_field.dart';
import 'entry_model.dart';

/// DTO sent to `PUT /api/vaults/{vaultId}/entries/{entryId}` to update
/// an existing entry. Patch semantics — only supplied fields are updated.
///
/// `icon` is intentionally omitted from the JSON when null so the
/// two-step custom-icon flow (entry update → S3 upload → icon PATCH)
/// does not wipe the existing icon between steps. To explicitly clear
/// the icon use a future dedicated PATCH endpoint, not a null here.
class UpdateEntryRequest {
  const UpdateEntryRequest({
    required this.label,
    this.description,
    this.icon,
    required this.type,
    required this.content,
    required this.deliveryPolicy,
    this.urlDomain,
    this.agentFields,
  });

  final String label;
  final String? description;
  final String? icon;

  /// Wire format — int ordinal of `EntryType` (`Key = 0`, `Credential = 1`).
  final int type;

  /// Re-encrypted JSONB envelope (new plaintext, same VK).
  final EntryContentModel content;
  final String deliveryPolicy;

  final String? urlDomain;

  /// Plaintext agent-visible mirror. Patch semantics: `null`
  /// leaves the stored set unchanged; an empty list clears it. The full
  /// edit flow always sends the current set (possibly empty) so removals
  /// take effect.
  final List<AgentField>? agentFields;

  Map<String, dynamic> toJson() => {
    'label': label,
    if (description != null) 'description': description,
    // Omit `icon` entirely when null — patch semantics on the backend
    // treat missing fields as "no change", which is exactly what we
    // want during the custom-icon two-step flow.
    if (icon != null) 'icon': icon,
    'type': type,
    'content': content.toJson(),
    'deliveryPolicy': deliveryPolicy,
    if (urlDomain != null) 'urlDomain': urlDomain,
    if (agentFields != null)
      'agentFields': agentFields!.map((f) => f.toJson()).toList(),
  };
}
