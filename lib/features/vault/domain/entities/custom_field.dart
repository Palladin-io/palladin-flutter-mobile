import 'dart:math';

import 'totp_config.dart';

/// Kind of a user-defined custom field on an entry (blob schema v2).
///
/// `text` and `concealed` carry a string value; `totp` carries a parsed
/// [TotpConfig] map. `unknown` covers reserved / future types (`url`,
/// `date`, `boolean`, …) — the UI ignores them but they are preserved
/// verbatim on round-trip so a newer client's fields are not dropped when
/// an older client edits the entry (forward-compat, spec §1).
enum CustomFieldType {
  text,
  concealed,
  totp,
  unknown;

  /// Parses a wire token. Anything the client does not recognize becomes
  /// [CustomFieldType.unknown] rather than throwing.
  static CustomFieldType fromWire(String? raw) => switch (raw) {
        'text' => CustomFieldType.text,
        'concealed' => CustomFieldType.concealed,
        'totp' => CustomFieldType.totp,
        _ => CustomFieldType.unknown,
      };
}

/// A single custom field inside the decrypted entry blob.
///
/// [value] holds the raw JSON value exactly as it appears in the blob: a
/// `String` for text/concealed, a `Map` for totp (a serialized
/// [TotpConfig]), or whatever an unknown future type stored. Keeping the
/// raw value lets us re-emit unknown fields unchanged on save.
class CustomField {
  const CustomField({
    required this.id,
    required this.label,
    required this.type,
    required this.rawType,
    this.value,
  });

  /// Client-generated stable id (uuid v4). Used to address the field for
  /// reorder / delete and by the agent CLI's `--field-id`.
  final String id;

  /// User-supplied display label. Encrypted at rest — treat as secret in
  /// logs (spec §7).
  final String label;

  /// Parsed field type. [CustomFieldType.unknown] for reserved / future
  /// tokens.
  final CustomFieldType type;

  /// Original type token from the blob. Preserved so an unknown type
  /// round-trips unchanged even though [type] collapses to `unknown`.
  final String rawType;

  /// Raw JSON value (`String` for text/concealed, `Map` for totp).
  final Object? value;

  /// String value for text / concealed fields (empty for other types).
  String get textValue => value is String ? value as String : '';

  /// Parsed TOTP config for a `totp` field, or null when the field is not
  /// a (valid) totp field.
  TotpConfig? get totp {
    if (type != CustomFieldType.totp) return null;
    final raw = value;
    if (raw is Map<String, dynamic>) return TotpConfig.fromJson(raw);
    if (raw is Map) {
      return TotpConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  CustomField copyWith({String? label, CustomFieldType? type, Object? value}) =>
      CustomField(
        id: id,
        label: label ?? this.label,
        type: type ?? this.type,
        rawType: type != null ? _wireFor(type) : rawType,
        value: value ?? this.value,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': rawType,
        'value': value,
      };

  factory CustomField.text({
    required String id,
    required String label,
    required String value,
  }) =>
      CustomField(
        id: id,
        label: label,
        type: CustomFieldType.text,
        rawType: 'text',
        value: value,
      );

  factory CustomField.concealed({
    required String id,
    required String label,
    required String value,
  }) =>
      CustomField(
        id: id,
        label: label,
        type: CustomFieldType.concealed,
        rawType: 'concealed',
        value: value,
      );

  factory CustomField.totpField({
    required String id,
    required String label,
    required TotpConfig config,
  }) =>
      CustomField(
        id: id,
        label: label,
        type: CustomFieldType.totp,
        rawType: 'totp',
        value: config.toJson(),
      );

  factory CustomField.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?) ?? '';
    return CustomField(
      id: (json['id'] as String?) ?? newId(),
      label: (json['label'] as String?) ?? '',
      type: CustomFieldType.fromWire(rawType),
      rawType: rawType,
      value: json['value'],
    );
  }

  /// Parses the `fields` array from a decrypted entry payload. Missing or
  /// malformed arrays yield an empty list; malformed individual entries
  /// are skipped rather than aborting the whole parse.
  static List<CustomField> listFromPayload(Map<String, dynamic> payload) {
    final raw = payload['fields'];
    if (raw is! List) return const [];
    final result = <CustomField>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        result.add(CustomField.fromJson(item));
      } else if (item is Map) {
        result.add(CustomField.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> listToJson(List<CustomField> fields) =>
      fields.map((f) => f.toJson()).toList(growable: false);

  static String _wireFor(CustomFieldType type) => switch (type) {
        CustomFieldType.text => 'text',
        CustomFieldType.concealed => 'concealed',
        CustomFieldType.totp => 'totp',
        CustomFieldType.unknown => 'text',
      };

  /// Generates a random RFC 4122 v4 UUID using a cryptographically secure
  /// source. Avoids pulling in a uuid package for a single call site.
  static String newId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
