import '../../domain/entities/agent_visibility_policy.dart';
import '../../domain/entities/entry_entity.dart';

/// Pure, schema-aware projection boundary for Agent Discovery and grants.
abstract final class AgentVisibilityProjector {
  /// Returns only policy-authorized fields that currently have a value.
  /// Optional fields may remain grant-enabled in the policy while being absent
  /// from a concrete Entry; those fields must not enter the authenticated grant
  /// field set until they exist.
  static List<String> grantableFieldIds({
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) {
    final values = _values(
      agentLabel: agentLabel,
      description: description,
      content: content,
    );
    return policy.fields.entries
        .where(
          (entry) =>
              entry.value != AgentFieldAccess.never &&
              entry.value != AgentFieldAccess.discovery &&
              values.containsKey(entry.key) &&
              values[entry.key] != null,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  static Map<String, dynamic> discovery({
    required EntryType type,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) {
    if (!policy.discoverable) {
      return {
        'schemaVersion': 1,
        'discoverable': false,
        'entryType': type.toWire(),
        'capabilities': const <String>[],
        'fields': const <String, String>{},
      };
    }
    final values = _values(
      agentLabel: agentLabel,
      description: description,
      content: content,
    );
    final fields = <String, dynamic>{};
    for (final entry in policy.fields.entries) {
      if (entry.value != AgentFieldAccess.discovery) continue;
      final value = values[entry.key];
      if (value != null && value.toString().isNotEmpty) {
        fields[entry.key] = value;
      }
    }
    return {
      'schemaVersion': 1,
      'discoverable': true,
      'agentLabel': agentLabel,
      'entryType': type.toWire(),
      'capabilities': _capabilities(type),
      'fields': fields,
    };
  }

  /// Builds a payload for an existing grant scope without widening policy.
  static Map<String, dynamic> grantPayload({
    required EntryType type,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
    required List<String> approvedFieldIds,
  }) {
    final values = _values(
      agentLabel: agentLabel,
      description: description,
      content: content,
    );
    final fields = <String, dynamic>{};
    for (final id in approvedFieldIds.toSet()) {
      final access = policy.fields[id];
      if (access == null || access == AgentFieldAccess.never) {
        throw const FormatException('Grant attempts to widen Entry policy');
      }
      final value = values[id];
      if (value == null) {
        throw const FormatException('Granted field is missing');
      }
      fields[id] = {'access': access.wireName, 'value': value};
    }
    if (fields.isEmpty) throw const FormatException('Grant scope is empty');
    return {'schemaVersion': 1, 'entryType': type.toWire(), 'fields': fields};
  }

  static Map<String, dynamic> _values({
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
  }) {
    final values = <String, dynamic>{
      'agentLabel': agentLabel,
      if (description.isNotEmpty) 'description': description,
      for (final id in const [
        'value',
        'notes',
        'username',
        'url',
        'password',
        'totp',
        'interpreter',
        'script',
        'refs',
        'cardholderName',
        'cardNumber',
        'expiryMonth',
        'expiryYear',
        'securityCode',
        'pin',
        'billingAddress',
      ])
        if (content[id] != null) id: content[id],
    };
    final url = content['url'];
    if (url is String) {
      final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
      if (uri != null && uri.host.isNotEmpty) values['urlDomain'] = uri.host;
    }
    final custom = content['fields'];
    if (custom is List) {
      for (final field in custom) {
        if (field is! Map || field['id'] is! String) continue;
        final id = field['id'] as String;
        if (field['value'] != null) values[id] = field['value'];
      }
    }
    return values;
  }

  static List<String> _capabilities(EntryType type) => switch (type) {
    EntryType.key => const ['get', 'exec'],
    EntryType.credential => const ['get', 'exec', 'inject'],
    EntryType.script => const ['exec'],
    EntryType.creditCard => const ['inject'],
  };
}
