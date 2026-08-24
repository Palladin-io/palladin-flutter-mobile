import '../../domain/entities/custom_field.dart';
import 'entry_model.dart';

/// DTO sent to `POST /api/vaults/{vaultId}/entries` to create a new
/// entry inside a vault.
///
/// All fields are JSON-serialized as camelCase. The encrypted payload
/// lives inside the [content] envelope — the backend stores it as a
/// JSONB column and never sees the plaintext.
class CreateEntryRequest {
  const CreateEntryRequest({
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

  /// JSONB envelope holding the base64-encoded ciphertext and matching
  /// nonce.
  final EntryContentModel content;
  final String deliveryPolicy;

  /// Optional plaintext URL domain (`stripe.com`) shown in the entry
  /// row's meta line. The full URL belongs inside the encrypted payload.
  final String? urlDomain;

  /// Plaintext mirror of the custom fields the owner marked agent-visible
  /// Discovery metadata like label/description — never a secret.
  final List<AgentField>? agentFields;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      'type': type,
      'content': content.toJson(),
      'deliveryPolicy': deliveryPolicy,
      if (urlDomain != null) 'urlDomain': urlDomain,
      if (agentFields != null)
        'agentFields': agentFields!.map((f) => f.toJson()).toList(),
    };
  }
}
