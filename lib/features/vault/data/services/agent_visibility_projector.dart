import '../../domain/entities/agent_visibility_policy.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/totp_config.dart';
import 'totp_service.dart';

/// Pure, schema-aware projection boundary for Agent Discovery and grants.
abstract final class AgentVisibilityProjector {
  /// Returns only policy-authorized fields that currently have a value.
  /// Optional fields may remain grant-enabled in the policy while being absent
  /// from a concrete Entry; those fields must not enter the authenticated grant
  /// field set until they exist.
  static List<String> grantableFieldIds({
    required EntryType type,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
  }) {
    if (type == EntryType.creditCard) return const [];
    final values = _values(
      agentLabel: agentLabel,
      description: description,
      content: content,
    );
    return policy.fields.entries
        .where((entry) {
          final policyId = _policyFieldId(type, entry.key);
          return entry.value != AgentFieldAccess.never &&
              entry.value != AgentFieldAccess.discovery &&
              _isRegisteredGrantField(type, policyId, content) &&
              values.containsKey(policyId) &&
              values[policyId] != null;
        })
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
    required String vaultId,
    required String agentLabel,
    required String description,
    required Map<String, dynamic> content,
    required AgentVisibilityPolicy policy,
    required List<String> approvedFieldIds,
    DateTime? now,
  }) {
    if (type == EntryType.creditCard) {
      throw const FormatException('Entry type is not registered for Grants');
    }
    final values = _values(
      agentLabel: agentLabel,
      description: description,
      content: content,
    );
    final fields = <Map<String, dynamic>>[];
    final canonicalIds = <String>{};
    for (final requestedId in approvedFieldIds.toSet()) {
      final policyId = _policyFieldId(type, requestedId);
      if (!_isRegisteredGrantField(type, policyId, content)) {
        throw const FormatException('Grant field is not registered');
      }
      final descriptor = _grantFieldDescriptor(type, policyId, content);
      final access =
          policy.fields[requestedId] ??
          policy.fields[policyId] ??
          policy.fields[descriptor.id];
      if (access != AgentFieldAccess.onGrantValue &&
          access != AgentFieldAccess.onGrantDerived &&
          access != AgentFieldAccess.onGrantRuntime) {
        throw const FormatException('Grant attempts to widen Entry policy');
      }
      final value = values[policyId];
      if (value == null) {
        throw const FormatException('Granted field is missing');
      }
      if (!canonicalIds.add(descriptor.id)) {
        throw const FormatException('Grant field ids are not unique');
      }
      fields.add({
        'id': descriptor.id,
        'kind': descriptor.kind,
        'mode': switch (access) {
          AgentFieldAccess.onGrantValue => 'value',
          AgentFieldAccess.onGrantDerived => 'derived',
          AgentFieldAccess.onGrantRuntime => 'runtime',
          _ => throw const FormatException('Grant field mode is invalid'),
        },
        'value': _grantValue(descriptor, value, vaultId, now),
      });
    }
    if (fields.isEmpty) throw const FormatException('Grant scope is empty');
    fields.sort(
      (left, right) =>
          (left['id']! as String).compareTo(right['id']! as String),
    );
    return {
      'schema': 'palladin.grant-payload.v1',
      'entryType': type.name,
      'fields': fields,
    };
  }

  /// Returns the exact field ids submitted with the Grant scope.
  ///
  /// Vault Protocol 2 carries this list structurally but does not bind it into
  /// the Grant payload AAD. Deriving it from the completed plaintext still
  /// prevents producer-side mapping drift and lets consumers reject an
  /// inconsistent structural record.
  static List<String> grantPayloadFieldIds(Map<String, dynamic> payload) {
    final fields = payload['fields'];
    if (payload['schema'] != 'palladin.grant-payload.v1' || fields is! List) {
      throw const FormatException('Malformed production Grant payload');
    }
    final ids = <String>[];
    for (final field in fields) {
      if (field is! Map || field['id'] is! String) {
        throw const FormatException('Malformed production Grant field');
      }
      ids.add(field['id'] as String);
    }
    if (ids.isEmpty || ids.toSet().length != ids.length) {
      throw const FormatException('Malformed production Grant field set');
    }
    final sorted = [...ids]..sort();
    if (!_sameStrings(ids, sorted)) {
      throw const FormatException('Production Grant fields are not sorted');
    }
    return List.unmodifiable(ids);
  }

  static String _policyFieldId(EntryType type, String id) => switch (id) {
    'key.value' when type == EntryType.key => 'value',
    'key.url' when type == EntryType.key => 'url',
    'key.notes' when type == EntryType.key => 'notes',
    'credential.username' when type == EntryType.credential => 'username',
    'credential.password' when type == EntryType.credential => 'password',
    'credential.url' when type == EntryType.credential => 'url',
    'credential.urlDomain' when type == EntryType.credential => 'urlDomain',
    'credential.totp' when type == EntryType.credential => 'totp',
    'credential.notes' when type == EntryType.credential => 'notes',
    'script.source' when type == EntryType.script => 'script',
    'script.interpreter' when type == EntryType.script => 'interpreter',
    'script.refs' when type == EntryType.script => 'refs',
    'script.notes' when type == EntryType.script => 'notes',
    final value
        when value.startsWith('creditCard.') && type == EntryType.creditCard =>
      value.substring('creditCard.'.length),
    final value when value.startsWith('custom:') => value.substring(
      'custom:'.length,
    ),
    _ => id,
  };

  static ({String id, String kind}) _grantFieldDescriptor(
    EntryType type,
    String id,
    Map<String, dynamic> content,
  ) {
    final standard = switch ((type, id)) {
      (EntryType.key, 'value') => (id: 'key.value', kind: 'concealed'),
      (EntryType.key, 'url') => (id: 'key.url', kind: 'url'),
      (EntryType.credential, 'username') => (
        id: 'credential.username',
        kind: 'text',
      ),
      (EntryType.credential, 'password') => (
        id: 'credential.password',
        kind: 'concealed',
      ),
      (EntryType.credential, 'url') => (id: 'credential.url', kind: 'url'),
      (EntryType.credential, 'totp') => (id: 'credential.totp', kind: 'totp'),
      (EntryType.key, 'notes') => (id: 'key.notes', kind: 'multiline'),
      (EntryType.credential, 'notes') => (
        id: 'credential.notes',
        kind: 'multiline',
      ),
      (EntryType.script, 'notes') => (id: 'script.notes', kind: 'multiline'),
      (EntryType.script, 'script') => (id: 'script.source', kind: 'script'),
      (EntryType.script, 'refs') => (id: 'script.refs', kind: 'refs'),
      _ => null,
    };
    if (standard != null) return standard;

    final custom = _customField(content, id);
    final customId = custom?['id'];
    final kind = custom?['type'];
    if (customId is! String ||
        !_isCanonicalUuid(customId) ||
        kind is! String ||
        !const {'text', 'multiline', 'concealed', 'totp'}.contains(kind)) {
      throw const FormatException('Grant field has no production mapping');
    }
    return (id: 'custom:$customId', kind: kind);
  }

  static Object? _grantValue(
    ({String id, String kind}) descriptor,
    Object? value,
    String vaultId,
    DateTime? now,
  ) {
    if (descriptor.kind == 'totp') {
      final config = switch (value) {
        final String raw => TotpConfig.parseUri(raw),
        final Map raw => TotpConfig.fromJson(Map<String, dynamic>.from(raw)),
        _ => null,
      };
      if (config == null) throw const FormatException('Invalid Grant TOTP');
      final code = const TotpService().generate(config, at: now);
      return {'code': code.code, 'expiresIn': code.secondsRemaining};
    }
    if (descriptor.kind == 'refs') {
      if (value is! List) throw const FormatException('Invalid Grant refs');
      return value
          .map((raw) {
            final referenceVaultId = raw is Map ? raw['vaultId'] : null;
            if (raw is! Map ||
                raw['env'] is! String ||
                raw['entryId'] is! String ||
                raw['field'] is! String ||
                (referenceVaultId != null && referenceVaultId is! String)) {
              throw const FormatException('Invalid Grant reference');
            }
            final effectiveVaultId = switch (referenceVaultId) {
              final String value when value.isNotEmpty => value,
              null => vaultId,
              _ => throw const FormatException('Invalid Grant reference'),
            };
            if (!_isCanonicalUuid(effectiveVaultId) ||
                !_isCanonicalUuid(raw['entryId'] as String)) {
              throw const FormatException('Invalid Grant reference scope');
            }
            return {
              'env': raw['env'],
              'vaultId': effectiveVaultId,
              'entryId': raw['entryId'],
              'fieldId': _referenceFieldId(raw['field'] as String),
            };
          })
          .toList(growable: false);
    }
    return value;
  }

  static String _referenceFieldId(String value) => switch (value) {
    'key.value' || 'key.url' || 'key.notes' => value,
    'credential.username' ||
    'credential.password' ||
    'credential.url' ||
    'credential.totp' ||
    'credential.notes' => value,
    'value' => 'key.value',
    'username' => 'credential.username',
    'password' => 'credential.password',
    'url' => 'credential.url',
    'totp' => 'credential.totp',
    'notes' => 'credential.notes',
    final id
        when id.startsWith('custom:') && _isCanonicalUuid(id.substring(7)) =>
      id,
    final id when _isCanonicalUuid(id) => 'custom:$id',
    _ => throw const FormatException('Invalid Grant reference field'),
  };

  static Map? _customField(Map<String, dynamic> content, String id) {
    final custom = content['fields'];
    if (custom is! List) return null;
    final rawId = id.startsWith('custom:') ? id.substring(7) : id;
    for (final field in custom) {
      if (field is Map && field['id'] == rawId) return field;
    }
    return null;
  }

  static bool _isRegisteredGrantField(
    EntryType type,
    String id,
    Map<String, dynamic> content,
  ) {
    final builtIn = switch (type) {
      EntryType.key => const {'value', 'url', 'notes'},
      EntryType.credential => const {
        'username',
        'password',
        'url',
        'totp',
        'notes',
      },
      EntryType.script => const {'script', 'refs', 'notes'},
      EntryType.creditCard => const <String>{},
    };
    if (builtIn.contains(id)) return true;
    final custom = _customField(content, id);
    final kind = custom?['type'];
    return custom?['id'] is String &&
        _isCanonicalUuid(custom!['id'] as String) &&
        const {'text', 'multiline', 'concealed', 'totp'}.contains(kind);
  }

  static bool _isCanonicalUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value);

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
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

  static List<String> _capabilities(EntryType _) => const [
    'get',
    'exec',
    'inject',
  ];
}
