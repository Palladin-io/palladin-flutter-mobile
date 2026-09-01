import 'custom_field.dart';
import 'member_index_entry.dart';

/// Type of vault entry — drives icon, payload schema, and reveal-panel
/// layout.
///
/// Mirrors the backend `EntryType` enum (`Key = 0`, `Credential = 1`,
/// `Script = 2`). Wire format is the integer ordinal stored on the
/// row-level `type` column. The decrypted payload schema is selected by
/// [EntryType] on the client; the JSONB content envelope itself carries
/// no discriminator.
enum EntryType {
  /// Single secret value — API key, token, etc.
  key,

  /// Username + password (+ optional URL).
  credential,

  /// Executable script with declared credential references (`refs`).
  script,

  /// Payment card details stored only inside the encrypted Entry payload.
  creditCard,
}

extension EntryTypeExtension on EntryType {
  /// Wire format used by the .NET API (int ordinal: `Key = 0`,
  /// `Credential = 1`, `Script = 2`).
  int toWire() => switch (this) {
    EntryType.key => 0,
    EntryType.credential => 1,
    EntryType.script => 2,
    EntryType.creditCard => 3,
  };

  /// Script source is never delivered through a regular Get grant. The
  /// runtime receives it only through the atomic Script execution package.
  String deliveryPolicyWire() => switch (this) {
    EntryType.script => 'execOnly',
    EntryType.creditCard => 'injectOnly',
    _ => 'standard',
  };

  int deliveryPolicyCode() => switch (this) {
    EntryType.script => 1,
    EntryType.creditCard => 2,
    _ => 0,
  };

  static EntryType fromWire(int value) => switch (value) {
    0 => EntryType.key,
    1 => EntryType.credential,
    2 => EntryType.script,
    3 => EntryType.creditCard,
    _ => throw FormatException('Unsupported Entry type ordinal: $value'),
  };
}

/// Plaintext payload for a credit-card Entry. All values remain encrypted.
class CreditCardPayload {
  const CreditCardPayload({
    required this.cardholderName,
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    this.billingAddress,
    this.notes,
    this.fields = const [],
  });
  final String cardholderName;
  final String cardNumber;
  final String expiryMonth;
  final String expiryYear;
  final String? billingAddress;
  final String? notes;
  final List<CustomField> fields;

  /// Rejects the retired dedicated card-verification fields.
  ///
  /// The pre-production cutover deliberately has no compatibility path for
  /// the former top-level CVV/CVC or PIN values. A neutral custom field may
  /// still use any user-selected label because only its stable `fields[]`
  /// shape is interpreted.
  static void rejectRetiredDedicatedFields(Map<String, dynamic> json) {
    if (json.containsKey('securityCode') || json.containsKey('pin')) {
      throw const FormatException(
        'Retired dedicated Credit Card field is not supported',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'v': 2,
    'type': 'CREDIT_CARD',
    'cardholderName': cardholderName,
    'cardNumber': cardNumber,
    'expiryMonth': expiryMonth,
    'expiryYear': expiryYear,
    if (billingAddress != null) 'billingAddress': billingAddress,
    if (notes != null) 'notes': notes,
    if (fields.isNotEmpty) 'fields': CustomField.listToJson(fields),
  };

  factory CreditCardPayload.fromJson(Map<String, dynamic> json) {
    rejectRetiredDedicatedFields(json);
    return CreditCardPayload(
      cardholderName: (json['cardholderName'] as String?) ?? '',
      cardNumber: (json['cardNumber'] as String?) ?? '',
      expiryMonth: (json['expiryMonth'] as String?) ?? '',
      expiryYear: (json['expiryYear'] as String?) ?? '',
      billingAddress: json['billingAddress'] as String?,
      notes: json['notes'] as String?,
      fields: CustomField.listFromPayload(json),
    );
  }
}

/// Domain representation of a single vault entry's metadata.
///
/// Encrypted payload (the actual secret) is intentionally NOT part of
/// this entity — it is loaded lazily from `GET /api/vaults/{vaultId}/entries/{id}`
/// when the user reveals the entry, and decrypted on-device.
class EntryEntity {
  static const unspecifiedRevision = '0';

  const EntryEntity({
    required this.id,
    required this.vaultId,
    required this.label,
    this.description,
    this.icon,
    required this.type,
    this.urlDomain,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.lifecycleState = MemberEntryState.active,
    this.currentRevision = unspecifiedRevision,
    this.currentKeyVersion = 1,
    this.corrupt = false,
  });

  /// Stable, server-issued identifier.
  final String id;

  /// Vault this entry belongs to.
  final String vaultId;

  /// User-supplied display label (e.g. "Stripe API Key").
  final String label;

  /// Optional description shown under the label in the row.
  final String? description;

  /// Optional icon name — same identifier vocabulary as
  /// `VaultVisuals.iconChoices` (`shield`, `code`, `cloud`, …).
  final String? icon;

  /// Entry type — see [EntryType].
  final EntryType type;

  /// Plaintext URL domain (e.g. `stripe.com`) shown as meta line. The
  /// full URL lives inside the encrypted payload.
  final String? urlDomain;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Timestamp of the most recent reveal/decrypt — null when never
  /// accessed.
  final DateTime? lastAccessedAt;

  /// Total number of reveals server-side.
  final int accessCount;
  final MemberEntryState lifecycleState;
  final String currentRevision;
  final int currentKeyVersion;
  final bool corrupt;

  EntryEntity copyWith({String? icon}) => EntryEntity(
    id: id,
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon ?? this.icon,
    type: type,
    urlDomain: urlDomain,
    createdAt: createdAt,
    updatedAt: updatedAt,
    lastAccessedAt: lastAccessedAt,
    accessCount: accessCount,
    lifecycleState: lifecycleState,
    currentRevision: currentRevision,
    currentKeyVersion: currentKeyVersion,
    corrupt: corrupt,
  );
}

/// Plaintext payload shape for a `KEY` entry. Lives only in memory
/// after decryption — never persisted in plaintext.
class KeyPayload {
  const KeyPayload({
    required this.value,
    this.url,
    this.notes,
    this.fields = const [],
  });

  /// The secret itself (token, API key, …).
  final String value;

  /// Optional associated URL (documentation link, service URL, …).
  final String? url;

  final String? notes;

  /// User-defined custom fields (blob schema v2). Empty for legacy v1
  /// entries.
  final List<CustomField> fields;

  Map<String, dynamic> toJson() => {
    'v': 2,
    'type': 'KEY',
    'value': value,
    if (url != null) 'url': url,
    if (notes != null) 'notes': notes,
    if (fields.isNotEmpty) 'fields': CustomField.listToJson(fields),
  };

  factory KeyPayload.fromJson(Map<String, dynamic> json) => KeyPayload(
    value: (json['value'] as String?) ?? '',
    url: json['url'] as String?,
    notes: json['notes'] as String?,
    fields: CustomField.listFromPayload(json),
  );
}

/// Plaintext payload shape for a `CREDENTIAL` entry. Lives only in
/// memory after decryption — never persisted in plaintext.
class CredentialPayload {
  const CredentialPayload({
    required this.username,
    required this.password,
    this.url,
    this.notes,
    this.totp,
    this.fields = const [],
  });

  final String username;
  final String password;
  final String? url;
  final String? notes;

  /// User-defined custom fields (blob schema v2). Empty for legacy v1
  /// entries.
  final List<CustomField> fields;

  /// Optional TOTP seed as an `otpauth://` URI. Populated when a
  /// credential is imported from a manager that carries a 2FA secret.
  /// Treated as an opaque blob on-device — the reveal UI may ignore it,
  /// but keeping it in the encrypted payload means it survives an
  /// import/export round-trip.
  final String? totp;

  Map<String, dynamic> toJson() => {
    'v': 2,
    'type': 'CREDENTIAL',
    'username': username,
    'password': password,
    if (url != null) 'url': url,
    if (notes != null) 'notes': notes,
    if (totp != null) 'totp': totp,
    if (fields.isNotEmpty) 'fields': CustomField.listToJson(fields),
  };

  factory CredentialPayload.fromJson(Map<String, dynamic> json) =>
      CredentialPayload(
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        url: json['url'] as String?,
        notes: json['notes'] as String?,
        totp: json['totp'] as String?,
        fields: CustomField.listFromPayload(json),
      );
}

/// Interpreter used to execute a `SCRIPT` entry (spec §5). Wire tokens are
/// the lowercase names carried inside the encrypted blob and validated
/// against this enum by the agent CLI.
enum ScriptInterpreter {
  bash,
  sh,
  node,
  python;

  String get wireName => name;

  /// Parses an exact canonical interpreter token and fails closed otherwise.
  static ScriptInterpreter fromName(String? raw) => switch (raw) {
    'bash' => ScriptInterpreter.bash,
    'sh' => ScriptInterpreter.sh,
    'node' => ScriptInterpreter.node,
    'python' => ScriptInterpreter.python,
    _ => throw FormatException('Unsupported Script interpreter: $raw'),
  };
}

/// One declared credential reference on a `SCRIPT` entry — an explicit
/// mapping of an environment variable name to a field on another entry
/// (spec §5, v1: no in-body substitution; `refs` is the whole contract).
class ScriptRef {
  const ScriptRef({
    required this.env,
    this.vaultId,
    required this.entryId,
    required this.field,
  });

  /// Environment variable name the agent CLI populates before exec.
  final String env;

  /// Vault the target entry lives in. Written on new blobs so the agent
  /// CLI can resolve a cross-vault reference; the CLI defaults a missing
  /// `vaultId` to the script's own vault (backward compatibility), so it
  /// is optional on parse.
  final String? vaultId;

  /// Target entry the value is pulled from (agent resolves via its own
  /// grant).
  final String entryId;

  /// Canonical field identifier on the target entry (`key.value`,
  /// `credential.password`, `notes`, or `custom:{uuid}`).
  final String field;

  Map<String, dynamic> toJson() => {
    'env': env,
    if (vaultId != null && vaultId!.isNotEmpty) 'vaultId': vaultId,
    'entryId': entryId,
    'fieldId': field,
  };

  factory ScriptRef.fromJson(Map<String, dynamic> json) => ScriptRef(
    // `env` is the current wire key; `placeholder` is read for
    // backward compatibility with earlier draft blobs.
    env: (json['env'] as String?) ?? (json['placeholder'] as String?) ?? '',
    vaultId: json['vaultId'] as String?,
    entryId: (json['entryId'] as String?) ?? '',
    field: (json['fieldId'] as String?) ?? (json['field'] as String?) ?? '',
  );

  static List<ScriptRef> listFromPayload(Map<String, dynamic> payload) {
    final raw = payload['refs'];
    if (raw is! List) return const [];
    final result = <ScriptRef>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        result.add(ScriptRef.fromJson(item));
      } else if (item is Map) {
        result.add(ScriptRef.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }
}

enum ScriptParameterType {
  string,
  integer,
  number,
  boolean;

  static ScriptParameterType fromWire(Object? raw) => switch (raw) {
    'string' => ScriptParameterType.string,
    'integer' => ScriptParameterType.integer,
    'number' => ScriptParameterType.number,
    'boolean' => ScriptParameterType.boolean,
    _ => throw FormatException('Unsupported Script parameter type: $raw'),
  };
}

/// A value-free, Agent-visible definition of one local execution parameter.
/// Parameter values are supplied to the CLI at runtime and never sent to the
/// Palladin backend.
class ScriptParameterDefinition {
  const ScriptParameterDefinition({
    required this.name,
    required this.description,
    required this.type,
    required this.required,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
    this.allowedValues = const [],
  });

  final String name;
  final String description;
  final ScriptParameterType type;
  final bool required;
  final num? minimum;
  final num? maximum;
  final int? minLength;
  final int? maxLength;
  final List<Object> allowedValues;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'type': type.name,
    'required': required,
    if (type == ScriptParameterType.string) ...{
      if (minLength != null) 'minLength': minLength,
      if (maxLength != null) 'maxLength': maxLength,
    } else ...{
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
    },
    if (allowedValues.isNotEmpty) 'enum': allowedValues,
  };

  factory ScriptParameterDefinition.fromJson(Map<String, dynamic> json) {
    if (json['name'] is! String ||
        json['description'] is! String ||
        json['required'] is! bool) {
      throw const FormatException('Malformed Script parameter');
    }
    final type = ScriptParameterType.fromWire(json['type']);
    final allowedKeys = <String>{
      'name',
      'description',
      'type',
      'required',
      'enum',
      if (type == ScriptParameterType.string) ...{'minLength', 'maxLength'},
      if (type == ScriptParameterType.integer ||
          type == ScriptParameterType.number) ...{
        'minimum',
        'maximum',
      },
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('Unknown Script parameter field');
    }
    final rawEnum = json['enum'];
    if (json.containsKey('enum') && rawEnum is! List) {
      throw const FormatException('Invalid Script parameter enum');
    }
    if (rawEnum is List &&
        (rawEnum.isEmpty ||
            rawEnum.length > 128 ||
            rawEnum.any((value) => value == null))) {
      throw const FormatException('Invalid Script parameter enum');
    }
    return ScriptParameterDefinition(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: type,
      required: json['required'] as bool? ?? false,
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
      minLength: json['minLength'] as int?,
      maxLength: json['maxLength'] as int?,
      allowedValues: rawEnum is List
          ? List<Object>.from(rawEnum, growable: false)
          : const [],
    );
  }
}

class ScriptExecutionMetadata {
  const ScriptExecutionMetadata({
    required this.description,
    this.parameters = const [],
    required this.returnResultToAgent,
  });

  static const int contractVersion = 1;
  final String description;
  final List<ScriptParameterDefinition> parameters;
  final bool returnResultToAgent;

  Map<String, dynamic> toJson() => {
    'contractVersion': contractVersion,
    'description': description.trim(),
    'parameters': parameters.map((value) => value.toJson()).toList(),
    'returnResultToAgent': returnResultToAgent,
  };

  factory ScriptExecutionMetadata.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
          (key) => !const {
            'contractVersion',
            'description',
            'parameters',
            'returnResultToAgent',
          }.contains(key),
        ) ||
        json['description'] is! String ||
        json['parameters'] is! List ||
        (json.containsKey('returnResultToAgent') &&
            json['returnResultToAgent'] is! bool)) {
      throw const FormatException('Malformed Script execution metadata');
    }
    if (json['contractVersion'] != contractVersion) {
      throw const FormatException('Unsupported Script execution metadata');
    }
    final rawParameters = json['parameters'] as List<dynamic>? ?? const [];
    if (rawParameters.any((value) => value is! Map)) {
      throw const FormatException('Malformed Script parameter definition');
    }
    final value = ScriptExecutionMetadata(
      description: json['description'] as String? ?? '',
      parameters: rawParameters
          .cast<Map>()
          .map(
            (value) => ScriptParameterDefinition.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(growable: false),
      // Missing on a legacy Script intentionally fails closed.
      returnResultToAgent: json['returnResultToAgent'] as bool? ?? false,
    );
    value.validate();
    return value;
  }

  void validate() {
    if (description.trim().isEmpty || description.length > 4096) {
      throw const FormatException('Invalid Script execution description');
    }
    if (parameters.length > 32) {
      throw const FormatException('Too many Script parameters');
    }
    final names = <String>{};
    for (final parameter in parameters) {
      if (!isScriptIdentifier(parameter.name) ||
          !names.add(parameter.name.toUpperCase()) ||
          parameter.description.trim().isEmpty ||
          parameter.description.length > 1024) {
        throw const FormatException('Invalid Script parameter');
      }
      if (parameter.minimum != null &&
          parameter.maximum != null &&
          parameter.minimum! > parameter.maximum!) {
        throw const FormatException('Invalid Script parameter range');
      }
      if (parameter.minLength != null &&
          parameter.maxLength != null &&
          parameter.minLength! > parameter.maxLength!) {
        throw const FormatException('Invalid Script parameter length');
      }
      if (parameter.type == ScriptParameterType.integer &&
          <num?>[
            parameter.minimum,
            parameter.maximum,
            ...parameter.allowedValues.whereType<num>(),
          ].whereType<num>().any((value) => value != value.roundToDouble())) {
        throw const FormatException('Invalid integer Script parameter');
      }
      if (parameter.minLength != null &&
              (parameter.minLength! < 0 || parameter.minLength! > 8192) ||
          parameter.maxLength != null &&
              (parameter.maxLength! < 0 || parameter.maxLength! > 8192)) {
        throw const FormatException('Invalid Script parameter length');
      }
      if (parameter.allowedValues.length > 128) {
        throw const FormatException('Invalid Script parameter enum');
      }
      final values = <String>{};
      for (final value in parameter.allowedValues) {
        final valid = switch (parameter.type) {
          ScriptParameterType.string => value is String && value.length <= 8192,
          ScriptParameterType.integer =>
            value is int && value.abs() <= 9007199254740991,
          ScriptParameterType.number => value is num && value.isFinite,
          ScriptParameterType.boolean => value is bool,
        };
        if (!valid || !values.add(value.toString())) {
          throw const FormatException('Invalid Script parameter enum');
        }
      }
    }
  }
}

const _reservedScriptEnvironmentNames = <String>{
  'BASHOPTS',
  'BASH_ENV',
  'CDPATH',
  'ENV',
  'GCONV_PATH',
  'GLOBIGNORE',
  'HOME',
  'HOSTALIASES',
  'IFS',
  'LD_PRELOAD',
  'LOCPATH',
  'LOGNAME',
  'NLSPATH',
  'NODE_OPTIONS',
  'NODE_PATH',
  'PATH',
  'PERL5LIB',
  'PERL5OPT',
  'PYTHONHOME',
  'PYTHONINSPECT',
  'PYTHONPATH',
  'PYTHONSTARTUP',
  'RUBYOPT',
  'SHELL',
  'SHELLOPTS',
  'TEMP',
  'TMP',
  'TMPDIR',
  'USER',
};

const _reservedScriptEnvironmentPrefixes = <String>[
  'CLAW_',
  'DYLD_',
  'LD_',
  'PALLADIN_',
];

bool isScriptIdentifier(String value) =>
    value.length <= 64 && RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

bool isAllowedScriptReferenceEnvironment(String value) {
  if (!isScriptIdentifier(value)) return false;
  final normalized = value.toUpperCase();
  return !_reservedScriptEnvironmentNames.contains(normalized) &&
      !_reservedScriptEnvironmentPrefixes.any(normalized.startsWith);
}

bool isScriptReferenceFieldId(String value) => RegExp(
  r'^(?:memberLabel|agentLabel|description|icon|color|entryType|key\.value|credential\.(?:username|password|url|urlDomain|totp)|creditCard\.(?:cardholderName|cardNumber|expiryMonth|expiryYear|billingAddress)|notes|script\.(?:source|interpreter|refs)|custom:[0-9a-fA-F-]{36})$',
).hasMatch(value);

/// Plaintext payload shape for a `SCRIPT` entry (spec §5). Lives only in
/// memory after decryption — never persisted in plaintext.
class ScriptPayload {
  const ScriptPayload({
    required this.script,
    this.interpreter = ScriptInterpreter.bash,
    this.notes,
    this.refs = const [],
    this.fields = const [],
    this.execution,
  });

  /// The script body. Shown to the human owner; delivered to agents only
  /// under the `exec` method.
  final String script;

  final ScriptInterpreter interpreter;
  final String? notes;

  /// Declared environment-variable → entry.field mappings.
  final List<ScriptRef> refs;

  /// User-defined custom fields (blob schema v2).
  final List<CustomField> fields;
  final ScriptExecutionMetadata? execution;

  Map<String, dynamic> toJson() => {
    'v': 2,
    'type': 'SCRIPT',
    'script': script,
    'interpreter': interpreter.wireName,
    if (notes != null) 'notes': notes,
    if (refs.isNotEmpty)
      'refs': refs.map((r) => r.toJson()).toList(growable: false),
    if (execution != null) 'execution': execution!.toJson(),
    if (fields.isNotEmpty) 'fields': CustomField.listToJson(fields),
  };

  factory ScriptPayload.fromJson(Map<String, dynamic> json) => ScriptPayload(
    script: (json['script'] as String?) ?? '',
    interpreter: ScriptInterpreter.fromName(json['interpreter'] as String?),
    notes: json['notes'] as String?,
    refs: ScriptRef.listFromPayload(json),
    fields: CustomField.listFromPayload(json),
    execution: json['execution'] is Map
        ? ScriptExecutionMetadata.fromJson(
            Map<String, dynamic>.from(json['execution'] as Map),
          )
        : null,
  );
}
