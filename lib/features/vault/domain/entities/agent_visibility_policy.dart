import 'entry_entity.dart';

/// Closed Agent field-access modes from the Vault protocol 2 contract.
enum AgentFieldAccess {
  never,
  discovery,
  onGrantValue,
  onGrantDerived,
  onGrantRuntime;

  String get wireName => name;

  static AgentFieldAccess parse(Object? value) => switch (value) {
    'never' => never,
    'discovery' => discovery,
    'onGrantValue' => onGrantValue,
    'onGrantDerived' => onGrantDerived,
    'onGrantRuntime' => onGrantRuntime,
    _ => throw const FormatException('Unsupported Agent field access'),
  };
}

/// Authenticated, per-Entry Agent Visibility Policy.
final class AgentVisibilityPolicy {
  AgentVisibilityPolicy({
    required this.discoverable,
    required Map<String, AgentFieldAccess> fields,
  }) : fields = Map.unmodifiable(fields);

  final bool discoverable;
  final Map<String, AgentFieldAccess> fields;

  AgentVisibilityPolicy copyWith({
    bool? discoverable,
    Map<String, AgentFieldAccess>? fields,
  }) => AgentVisibilityPolicy(
    discoverable: discoverable ?? this.discoverable,
    fields: fields ?? this.fields,
  );

  Map<String, dynamic> toJson() => {
    'discoverable': discoverable,
    'fields': fields.map((key, value) => MapEntry(key, value.wireName)),
  };

  /// Parses and validates the policy against the concrete Entry schema.
  factory AgentVisibilityPolicy.fromJson(
    EntryType type,
    Map<String, dynamic> json, {
    required Map<String, dynamic> content,
  }) {
    final discoverable = json['discoverable'];
    final rawFields = json['fields'];
    if (discoverable is! bool || rawFields is! Map) {
      throw const FormatException('Malformed Agent Visibility Policy');
    }
    final fields = <String, AgentFieldAccess>{};
    for (final entry in rawFields.entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid policy field id');
      }
      final id = entry.key as String;
      final access = AgentFieldAccess.parse(entry.value);
      if (!allowedFor(type, id, content).contains(access)) {
        throw const FormatException('Invalid access for Entry field');
      }
      fields[id] = access;
    }
    if (discoverable && fields['agentLabel'] != AgentFieldAccess.discovery) {
      throw const FormatException('Discoverable Entry requires Agent label');
    }
    return AgentVisibilityPolicy(discoverable: discoverable, fields: fields);
  }

  /// Returns the closed set accepted for one schema field.
  static Set<AgentFieldAccess> allowedFor(
    EntryType type,
    String id,
    Map<String, dynamic> content,
  ) {
    return switch (id) {
      'agentLabel' => const {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      },
      'description' => const {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
        AgentFieldAccess.onGrantValue,
      },
      'notes' when type == EntryType.script || type == EntryType.creditCard =>
        const {AgentFieldAccess.never, AgentFieldAccess.onGrantRuntime},
      'notes' => const {AgentFieldAccess.never, AgentFieldAccess.onGrantValue},
      'value' when type == EntryType.key => const {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantValue,
      },
      'username' when type == EntryType.credential => const {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
        AgentFieldAccess.onGrantValue,
      },
      'urlDomain' when type == EntryType.credential => const {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      },
      'url' || 'password' when type == EntryType.credential => const {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantValue,
      },
      'totp' when type == EntryType.credential => const {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantDerived,
      },
      'interpreter' when type == EntryType.script => const {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      },
      'script' || 'refs' when type == EntryType.script => const {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantRuntime,
      },
      'cardholderName' when type == EntryType.creditCard => const {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantRuntime,
      },
      'cardNumber' || 'expiryMonth' || 'expiryYear' || 'billingAddress'
          when type == EntryType.creditCard =>
        const {AgentFieldAccess.never, AgentFieldAccess.onGrantRuntime},
      _ => _customAllowed(type, id, content),
    };
  }

  static Set<AgentFieldAccess> _customAllowed(
    EntryType type,
    String id,
    Map<String, dynamic> content,
  ) {
    final raw = content['fields'];
    if (raw is! List) return const {AgentFieldAccess.never};
    Map<dynamic, dynamic>? field;
    for (final candidate in raw) {
      if (candidate is Map && candidate['id'] == id) {
        field = candidate;
        break;
      }
    }
    if (field == null) return const {AgentFieldAccess.never};
    final fieldType = field['type'];
    if (fieldType == 'totp') {
      return const {AgentFieldAccess.never, AgentFieldAccess.onGrantDerived};
    }
    if (fieldType != 'text' &&
        fieldType != 'multiline' &&
        fieldType != 'concealed') {
      return const {AgentFieldAccess.never};
    }
    return type == EntryType.script || type == EntryType.creditCard
        ? const {AgentFieldAccess.never, AgentFieldAccess.onGrantRuntime}
        : const {
            AgentFieldAccess.never,
            AgentFieldAccess.discovery,
            AgentFieldAccess.onGrantValue,
          };
  }
}
