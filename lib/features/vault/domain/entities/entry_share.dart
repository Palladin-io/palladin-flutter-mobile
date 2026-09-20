enum EntryShareErrorKind { invalidSnapshot, invalidLink }

/// Deliberately contains no input, parser diagnostics or crypto exception.
final class EntryShareException implements Exception {
  const EntryShareException(this.kind);
  final EntryShareErrorKind kind;
  @override
  String toString() => 'EntryShareException(${kind.name})';
}

final class EntryShareScope {
  const EntryShareScope({
    required this.shareId,
    required this.organizationId,
    required this.vaultId,
    required this.entryId,
    required this.sourceRevision,
    required this.expiresAt,
  });
  final String shareId,
      organizationId,
      vaultId,
      entryId,
      sourceRevision,
      expiresAt;
}

final class EntryShareCiphertext {
  const EntryShareCiphertext({required this.nonce, required this.ciphertext});
  final String nonce, ciphertext;
}

final class EntryShareField {
  const EntryShareField._(this.id, this.label, this.type, this.value);
  final String id, label, type, value;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'type': type,
    'value': value,
  };
}

/// Independently decrypted input, never a backend-owned lifecycle validator.
/// Constructors are private so every snapshot passes the wire schema once.
final class EntryShareSnapshot {
  EntryShareSnapshot._(this.title, this.entryType, List<EntryShareField> fields)
    : fields = List.unmodifiable(fields);
  final String title, entryType;
  final List<EntryShareField> fields;
  static const schema = 'palladin.entry-share.v1';

  factory EntryShareSnapshot.fromJson(Object? value) {
    const invalid = EntryShareException(EntryShareErrorKind.invalidSnapshot);
    if (value is! Map ||
        !_keys(value, {'schema', 'title', 'entryType', 'fields'}) ||
        value['schema'] != schema ||
        !_text(value['title'], 1, 512) ||
        !{
          'key',
          'credential',
          'script',
          'creditCard',
        }.contains(value['entryType'])) {
      throw invalid;
    }
    final rawFields = value['fields'];
    if (rawFields is! List || rawFields.isEmpty || rawFields.length > 256) {
      throw invalid;
    }
    final fields = <EntryShareField>[];
    final ids = <String>{};
    final entryType = value['entryType'] as String;
    for (final field in rawFields) {
      if (field is! Map ||
          !_keys(field, {'id', 'label', 'type', 'value'}) ||
          !_text(field['id'], 1, 160) ||
          !_text(field['label'], 0, 256) ||
          !_text(field['value'], 0, 262144) ||
          !{'text', 'multiline', 'concealed', 'totp'}.contains(field['type'])) {
        throw invalid;
      }
      final id = field['id'] as String;
      final type = field['type'] as String;
      if (!ids.add(id)) throw invalid;
      final custom = id.startsWith('custom:') && id.length > 7;
      final native =
          _nativeTypes[id] == type &&
          (id == 'notes' ||
              id == 'description' ||
              id.startsWith('$entryType.'));
      if (!custom && !native) throw invalid;
      fields.add(
        EntryShareField._(
          id,
          field['label'] as String,
          type,
          field['value'] as String,
        ),
      );
    }
    return EntryShareSnapshot._(value['title'] as String, entryType, fields);
  }

  Map<String, Object?> toJson() => {
    'schema': schema,
    'title': title,
    'entryType': entryType,
    'fields': fields.map((field) => field.toJson()).toList(),
  };

  static bool _keys(Map value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);
  static bool _text(Object? value, int min, int max) =>
      value is String && value.length >= min && value.length <= max;
  static const _nativeTypes = {
    'credential.username': 'text',
    'credential.password': 'concealed',
    'credential.url': 'text',
    'credential.totp': 'totp',
    'key.value': 'concealed',
    'key.url': 'text',
    'script.source': 'multiline',
    'script.interpreter': 'text',
    'creditCard.cardholderName': 'text',
    'creditCard.cardNumber': 'concealed',
    'creditCard.expiryMonth': 'text',
    'creditCard.expiryYear': 'text',
    'creditCard.billingAddress': 'multiline',
    'notes': 'multiline',
    'description': 'multiline',
  };
}
