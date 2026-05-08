/// DTO sent to `POST /api/vaults/{vaultId}/entries` to create a new
/// entry inside a vault.
///
/// All fields are JSON-serialized as camelCase. [encryptedBlob] and
/// [nonce] are base64-encoded — the backend stores them as `bytea` and
/// never sees the plaintext payload.
class CreateEntryRequest {
  const CreateEntryRequest({
    required this.label,
    this.description,
    this.icon,
    required this.type,
    required this.encryptedBlob,
    required this.nonce,
    this.urlDomain,
  });

  final String label;
  final String? description;
  final String? icon;

  /// Wire format — `'KEY'` / `'CREDENTIAL'`.
  final String type;

  /// Base64-encoded ciphertext from `crypto_secretbox_easy(payloadJson, nonce, vaultKey)`.
  final String encryptedBlob;

  /// Base64-encoded 24-byte nonce that was used to seal [encryptedBlob].
  final String nonce;

  /// Optional plaintext URL domain (`stripe.com`) shown in the entry
  /// row's meta line. The full URL belongs inside the encrypted payload.
  final String? urlDomain;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      'type': type,
      'encryptedBlob': encryptedBlob,
      'nonce': nonce,
      if (urlDomain != null) 'urlDomain': urlDomain,
    };
  }
}
