import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// A malformed or unsupported Vault v2 plaintext document.
final class VaultPlaintextFormatException implements Exception {
  const VaultPlaintextFormatException(this.message);

  final String message;

  @override
  String toString() => 'VaultPlaintextFormatException: $message';
}

/// Closed Entry type used by Vault v2 plaintexts.
enum VaultEntryType {
  key,
  credential,
  script,
  creditCard;

  static VaultEntryType parse(Object? value) => switch (value) {
    'key' => key,
    'credential' => credential,
    'script' => script,
    'creditCard' => creditCard,
    _ => throw VaultPlaintextFormatException('Unknown entryType.'),
  };
}

/// Closed per-field Agent access policy.
enum AgentFieldAccess {
  never,
  discovery,
  onGrantValue,
  onGrantDerived,
  onGrantRuntime;

  static AgentFieldAccess parse(Object? value) => switch (value) {
    'never' => never,
    'discovery' => discovery,
    'onGrantValue' => onGrantValue,
    'onGrantDerived' => onGrantDerived,
    'onGrantRuntime' => onGrantRuntime,
    _ => throw VaultPlaintextFormatException('Unknown AgentFieldAccess.'),
  };
}

/// Grant-payload result mode derived from [AgentFieldAccess].
enum GrantFieldMode { value, derived, runtime }

/// Closed encrypted icon reference. Catalog URLs are admitted only together
/// with their immutable catalog identity and revision.
sealed class VaultPlaintextIcon {
  const VaultPlaintextIcon();

  Map<String, Object> toJson();

  static VaultPlaintextIcon? fromReference(String? value) {
    final reference = value?.trim() ?? '';
    if (reference.isEmpty) return null;
    if (reference.startsWith('public-asset:') && reference.length > 13) {
      final parts = reference.substring(13).split('|');
      if (parts.length != 3) {
        throw const VaultPlaintextFormatException(
          'Invalid public asset icon reference.',
        );
      }
      final revision = int.tryParse(parts[1]);
      Uri? url;
      try {
        url = Uri.tryParse(Uri.decodeComponent(parts[2]));
      } on FormatException {
        throw const VaultPlaintextFormatException(
          'Invalid public asset icon reference.',
        );
      }
      if (revision == null || revision < 1 || url == null) {
        throw const VaultPlaintextFormatException(
          'Invalid public asset icon reference.',
        );
      }
      return PublicAssetVaultIcon(parts[0], revision, url.toString());
    }
    if (reference.startsWith('asset:') && reference.length > 6) {
      return EncryptedAssetVaultIcon(reference.substring(6));
    }
    if (reference.startsWith('builtin:') && reference.length > 8) {
      return GlyphVaultIcon(reference.substring(8));
    }
    if (reference.startsWith('http://') || reference.startsWith('https://')) {
      throw const VaultPlaintextFormatException(
        'Remote icon URLs are not canonical Vault plaintext references.',
      );
    }
    return GlyphVaultIcon(reference);
  }

  static VaultPlaintextIcon? parse(Object? value) {
    if (value == null) return null;
    final map = _object(value, 'icon');
    final kind = _string(map['kind'], 'icon.kind', min: 1, max: 32);
    _exactKeys(map, switch (kind) {
      'encryptedAsset' => const {'kind', 'assetId'},
      'publicAsset' => const {'kind', 'assetId', 'revision', 'url'},
      _ => const {'kind', 'value'},
    }, 'icon');
    return switch (kind) {
      'glyph' => GlyphVaultIcon(
        _string(map['value'], 'icon.value', min: 1, max: 200),
      ),
      'encryptedAsset' => EncryptedAssetVaultIcon(
        _string(map['assetId'], 'icon.assetId', min: 1, max: 512),
      ),
      'publicAsset' => PublicAssetVaultIcon(
        _string(map['assetId'], 'icon.assetId', min: 1, max: 512),
        _integer(map['revision'], 'icon.revision', min: 1),
        _publicAssetUrl(map['url']),
      ),
      _ => throw const VaultPlaintextFormatException('Unknown icon kind.'),
    };
  }
}

final class PublicAssetVaultIcon extends VaultPlaintextIcon {
  const PublicAssetVaultIcon(this.assetId, this.revision, this.url);
  final String assetId;
  final int revision;
  final String url;

  String get reference =>
      'public-asset:$assetId|$revision|${Uri.encodeComponent(url)}';

  @override
  Map<String, Object> toJson() => {
    'kind': 'publicAsset',
    'assetId': assetId,
    'revision': revision,
    'url': url,
  };
}

final class GlyphVaultIcon extends VaultPlaintextIcon {
  const GlyphVaultIcon(this.value);
  final String value;

  @override
  Map<String, Object> toJson() => {'kind': 'glyph', 'value': value};
}

final class EncryptedAssetVaultIcon extends VaultPlaintextIcon {
  const EncryptedAssetVaultIcon(this.assetId);
  final String assetId;

  @override
  Map<String, Object> toJson() => {
    'kind': 'encryptedAsset',
    'assetId': assetId,
  };
}

/// Encrypted Vault metadata plaintext.
final class MemberVaultMetadata {
  const MemberVaultMetadata({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.grantMode,
  });

  static const schema = 'palladin.member-vault-metadata.v1';
  final String name;
  final String? description;
  final VaultPlaintextIcon? icon;
  final String? color;
  final String grantMode;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'name': name,
    'description': description,
    'icon': icon?.toJson(),
    'color': color,
    'grantMode': grantMode,
  };

  factory MemberVaultMetadata.fromJson(Map<String, Object?> json) {
    _exactKeys(json, const {
      'schema',
      'name',
      'description',
      'icon',
      'color',
      'grantMode',
    }, schema);
    _schema(json, schema);
    final grantMode = _string(json['grantMode'], 'grantMode', min: 1, max: 16);
    if (grantMode != 'full' && grantMode != 'granular') {
      throw const VaultPlaintextFormatException('Unknown grantMode.');
    }
    return MemberVaultMetadata(
      name: _string(json['name'], 'name', min: 1, max: 200),
      description: _nullableString(json, 'description', max: 2000),
      icon: VaultPlaintextIcon.parse(_required(json, 'icon')),
      color: _color(_required(json, 'color')),
      grantMode: grantMode,
    );
  }
}

/// Safe custom field admitted to the Member list/search projection.
final class MemberIndexCustomField {
  const MemberIndexCustomField({
    required this.id,
    required this.label,
    required this.value,
  });

  final String id;
  final String label;
  final String value;

  Map<String, Object> toJson() => {'id': id, 'label': label, 'value': value};
}

/// Small Member-only list/search projection. It cannot contain secrets.
final class MemberIndex {
  const MemberIndex({
    required this.entryType,
    required this.memberLabel,
    required this.description,
    required this.icon,
    required this.color,
    required this.username,
    required this.urlDomain,
    required this.customIndex,
  });

  static const schema = 'palladin.member-index.v1';
  final VaultEntryType entryType;
  final String memberLabel;
  final String? description;
  final VaultPlaintextIcon? icon;
  final String? color;
  final String? username;
  final String? urlDomain;
  final List<MemberIndexCustomField> customIndex;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'entryType': entryType.name,
    'memberLabel': memberLabel,
    'description': description,
    'icon': icon?.toJson(),
    'color': color,
    'username': username,
    'urlDomain': urlDomain,
    'customIndex': customIndex.map((value) => value.toJson()).toList(),
  };

  factory MemberIndex.fromJson(Map<String, Object?> json) {
    _exactKeys(json, const {
      'schema',
      'entryType',
      'memberLabel',
      'description',
      'icon',
      'color',
      'username',
      'urlDomain',
      'customIndex',
    }, schema);
    _schema(json, schema);
    final rawCustom = _required(json, 'customIndex');
    if (rawCustom is! List || rawCustom.length > 20) {
      throw const VaultPlaintextFormatException('Invalid customIndex.');
    }
    final custom = rawCustom
        .map((value) {
          final item = _object(value, 'customIndex item');
          _exactKeys(item, const {'id', 'label', 'value'}, 'customIndex item');
          final id = _string(item['id'], 'customIndex.id', min: 43, max: 43);
          if (!RegExp(
            r'^custom:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(id)) {
            throw const VaultPlaintextFormatException(
              'Invalid customIndex id.',
            );
          }
          return MemberIndexCustomField(
            id: id,
            label: _string(
              item['label'],
              'customIndex.label',
              min: 1,
              max: 256,
            ),
            value: _string(
              item['value'],
              'customIndex.value',
              min: 1,
              max: 8192,
            ),
          );
        })
        .toList(growable: false);
    return MemberIndex(
      entryType: VaultEntryType.parse(json['entryType']),
      memberLabel: _string(
        json['memberLabel'],
        'memberLabel',
        min: 1,
        max: 256,
      ),
      description: _nullableString(json, 'description', max: 2048),
      icon: VaultPlaintextIcon.parse(_required(json, 'icon')),
      color: _color(_required(json, 'color')),
      username: _nullableString(json, 'username', max: 8192),
      // Web keeps the imported URL-domain projection as a normalized string.
      // It can contain legacy Android/app URLs and is therefore not limited to
      // the DNS hostname ceiling. Hostname normalization happens only when an
      // an optional public icon is reserved before encryption.
      urlDomain: _nullableString(json, 'urlDomain', max: 8192),
      customIndex: custom,
    );
  }
}

/// A canonical custom field in MemberSecret.
final class VaultCustomField {
  const VaultCustomField({
    required this.id,
    required this.label,
    required this.kind,
    required this.value,
    this.includeInMemberIndex = false,
  });

  final String id;
  final String label;
  final String kind;
  final Object? value;
  final bool includeInMemberIndex;

  String get fieldId => 'custom:$id';

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'kind': kind,
    'value': value,
    'includeInMemberIndex': includeInMemberIndex,
  };
}

/// Closed content union for MemberSecret.
sealed class MemberSecretContent {
  const MemberSecretContent({required this.customFields});
  final List<VaultCustomField> customFields;
  Map<String, Object?> toJson();
  Map<String, Object?> fieldValues();
}

final class KeySecretContent extends MemberSecretContent {
  const KeySecretContent({
    required this.value,
    this.url,
    required this.notes,
    required super.customFields,
  });
  final String value;
  final String? url;
  final String? notes;

  @override
  Map<String, Object?> toJson() => {
    'value': value,
    'url': url,
    'notes': notes,
    'customFields': customFields.map((field) => field.toJson()).toList(),
  };

  @override
  Map<String, Object?> fieldValues() => {
    'key.value': value,
    if (url != null) 'key.url': url,
    'notes': notes,
  };
}

final class CredentialSecretContent extends MemberSecretContent {
  const CredentialSecretContent({
    required this.username,
    required this.password,
    required this.url,
    required this.urlDomain,
    required this.totp,
    required this.notes,
    required super.customFields,
  });
  final String username;
  final String password;
  final String? url;
  final String? urlDomain;
  final Map<String, Object?>? totp;
  final String? notes;

  @override
  Map<String, Object?> toJson() => {
    'username': username,
    'password': password,
    'url': url,
    'urlDomain': urlDomain,
    'totp': totp,
    'notes': notes,
    'customFields': customFields.map((field) => field.toJson()).toList(),
  };

  @override
  Map<String, Object?> fieldValues() => {
    'credential.username': username,
    'credential.password': password,
    'credential.url': url,
    'credential.urlDomain': urlDomain,
    'credential.totp': totp,
    'notes': notes,
  };
}

final class ScriptSecretContent extends MemberSecretContent {
  const ScriptSecretContent({
    required this.source,
    required this.interpreter,
    required this.refs,
    required this.notes,
    required super.customFields,
  });
  final String source;
  final String interpreter;
  final List<Map<String, Object?>> refs;
  final String? notes;

  @override
  Map<String, Object?> toJson() => {
    'source': source,
    'interpreter': interpreter,
    'refs': refs,
    'notes': notes,
    'customFields': customFields.map((field) => field.toJson()).toList(),
  };

  @override
  Map<String, Object?> fieldValues() => {
    'script.source': source,
    'script.interpreter': interpreter,
    'script.refs': refs,
    'notes': notes,
  };
}

final class CreditCardSecretContent extends MemberSecretContent {
  const CreditCardSecretContent({
    required this.cardholderName,
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.billingAddress,
    required this.notes,
    required super.customFields,
  });
  final String cardholderName, cardNumber, expiryMonth, expiryYear;
  final String? billingAddress, notes;
  @override
  Map<String, Object?> toJson() => {
    'cardholderName': cardholderName,
    'cardNumber': cardNumber,
    'expiryMonth': expiryMonth,
    'expiryYear': expiryYear,
    'billingAddress': billingAddress,
    'notes': notes,
    'customFields': customFields.map((field) => field.toJson()).toList(),
  };
  @override
  Map<String, Object?> fieldValues() => {
    'creditCard.cardholderName': cardholderName,
    'creditCard.cardNumber': cardNumber,
    'creditCard.expiryMonth': expiryMonth,
    'creditCard.expiryYear': expiryYear,
    'creditCard.billingAddress': billingAddress,
    'notes': notes,
  };
}

/// Canonical complete Entry state and exact Agent policy.
final class MemberSecret {
  MemberSecret({
    required this.entryType,
    required this.memberLabel,
    required this.agentLabel,
    required this.description,
    required this.icon,
    required this.color,
    required this.discoverable,
    required this.content,
    required Map<String, AgentFieldAccess> agentFieldAccess,
  }) : agentFieldAccess = Map.unmodifiable(agentFieldAccess) {
    _validate();
  }

  static const schema = 'palladin.member-secret.v1';
  final VaultEntryType entryType;
  final String memberLabel;
  final String? agentLabel;
  final String? description;
  final VaultPlaintextIcon? icon;
  final String? color;
  final bool discoverable;
  final MemberSecretContent content;
  final Map<String, AgentFieldAccess> agentFieldAccess;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'entryType': entryType.name,
    'memberLabel': memberLabel,
    'agentLabel': agentLabel,
    'description': description,
    'icon': icon?.toJson(),
    'color': color,
    'discoverable': discoverable,
    'content': content.toJson(),
    'agentFieldAccess': agentFieldAccess.map(
      (key, value) => MapEntry(key, value.name),
    ),
  };

  void _validate() {
    if (memberLabel.isEmpty || memberLabel.length > 200) {
      throw const VaultPlaintextFormatException('Invalid memberLabel.');
    }
    if (discoverable && (agentLabel == null || agentLabel!.isEmpty)) {
      throw const VaultPlaintextFormatException(
        'Discoverable Entry requires agentLabel.',
      );
    }
    if (!discoverable && agentLabel != null) {
      throw const VaultPlaintextFormatException(
        'Non-discoverable Entry cannot carry agentLabel.',
      );
    }
    final required = <String>{
      'memberLabel',
      'agentLabel',
      'description',
      'icon',
      'color',
      'entryType',
      ...content.fieldValues().keys,
      ...content.customFields.map((field) => field.fieldId),
    };
    if (!agentFieldAccess.keys.toSet().containsAll(required) ||
        agentFieldAccess.length != required.length) {
      throw const VaultPlaintextFormatException(
        'agentFieldAccess must exactly cover all fields.',
      );
    }
    if ((discoverable &&
            (agentFieldAccess['entryType'] != AgentFieldAccess.discovery ||
                agentFieldAccess['agentLabel'] !=
                    AgentFieldAccess.discovery)) ||
        (!discoverable &&
            agentFieldAccess.values.contains(AgentFieldAccess.discovery))) {
      throw const VaultPlaintextFormatException('Invalid discovery policy.');
    }
    for (final entry in agentFieldAccess.entries) {
      _validateMode(entry.key, entry.value);
    }
  }

  void _validateMode(String id, AgentFieldAccess access) {
    final allowed = switch (id) {
      'memberLabel' || 'icon' || 'color' => {AgentFieldAccess.never},
      'description' => {AgentFieldAccess.never, AgentFieldAccess.discovery},
      'entryType' ||
      'agentLabel' => {AgentFieldAccess.never, AgentFieldAccess.discovery},
      'credential.username' || 'credential.urlDomain' => {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
        AgentFieldAccess.onGrantValue,
      },
      'creditCard.cardholderName' => {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantRuntime,
      },
      'creditCard.cardNumber' ||
      'creditCard.expiryMonth' ||
      'creditCard.expiryYear' ||
      'creditCard.billingAddress' => {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantRuntime,
      },
      'credential.totp' => {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantDerived,
      },
      'script.source' || 'script.refs' => {
        AgentFieldAccess.never,
        AgentFieldAccess.onGrantRuntime,
      },
      'script.interpreter' => {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      },
      _ when id.startsWith('custom:') => _customAllowed(id),
      _ => {AgentFieldAccess.never, AgentFieldAccess.onGrantValue},
    };
    if (!allowed.contains(access)) {
      throw VaultPlaintextFormatException('Unsafe Agent access for $id.');
    }
  }

  Set<AgentFieldAccess> _customAllowed(String id) {
    final field = content.customFields.singleWhere(
      (value) => value.fieldId == id,
    );
    return switch (field.kind) {
      'totp' => {AgentFieldAccess.never, AgentFieldAccess.onGrantDerived},
      'text' || 'multiline' || 'concealed' => {
        AgentFieldAccess.never,
        if (entryType == VaultEntryType.script ||
            entryType == VaultEntryType.creditCard)
          AgentFieldAccess.onGrantRuntime
        else
          AgentFieldAccess.onGrantValue,
        if (field.kind != 'concealed') AgentFieldAccess.discovery,
      },
      _ => throw const VaultPlaintextFormatException('Unknown custom kind.'),
    };
  }
}

/// One sorted Agent projection field.
final class ProjectedAgentField {
  const ProjectedAgentField({
    required this.id,
    required this.value,
    this.kind,
    this.mode,
  });
  final String id;
  final Object? value;
  final String? kind;
  final GrantFieldMode? mode;

  Map<String, Object?> toJson() => {
    'id': id,
    if (kind != null) 'kind': kind,
    if (mode != null) 'mode': mode!.name,
    'value': value,
  };
}

/// Projects canonical Member state into audience-specific plaintexts.
abstract final class VaultPlaintextProjector {
  static MemberIndex memberIndex(MemberSecret secret) {
    final content = secret.content;
    final credential = content is CredentialSecretContent ? content : null;
    final custom = content.customFields
        .where(
          (field) =>
              field.includeInMemberIndex &&
              (field.kind == 'text' || field.kind == 'multiline'),
        )
        .take(20)
        .map(
          (field) => MemberIndexCustomField(
            id: field.fieldId,
            label: field.label,
            value: field.value as String,
          ),
        )
        .toList(growable: false);
    return MemberIndex(
      entryType: secret.entryType,
      memberLabel: secret.memberLabel,
      description: secret.description,
      icon: secret.icon,
      color: secret.color,
      username: credential?.username,
      urlDomain: credential?.urlDomain,
      customIndex: custom,
    );
  }

  static Map<String, Object?>? agentDiscovery(MemberSecret secret) {
    if (!secret.discoverable) return null;
    final values = _allValues(secret);
    final fields =
        secret.agentFieldAccess.entries
            .where(
              (entry) =>
                  entry.value == AgentFieldAccess.discovery &&
                  entry.key != 'agentLabel' &&
                  entry.key != 'entryType',
            )
            .map(
              (entry) =>
                  ProjectedAgentField(id: entry.key, value: values[entry.key]),
            )
            .toList()
          ..sort((left, right) => left.id.compareTo(right.id));
    return {
      'schema': 'palladin.agent-discovery.v1',
      'entryType': secret.entryType.name,
      'agentLabel': secret.agentLabel,
      'capabilities': _capabilities(secret),
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }

  static Map<String, Object?> grantPayload(
    MemberSecret secret,
    Set<String> fieldIds,
  ) {
    final values = _allValues(secret);
    final fields = fieldIds.map((id) {
      final access = secret.agentFieldAccess[id];
      final mode = switch (access) {
        AgentFieldAccess.onGrantValue => GrantFieldMode.value,
        AgentFieldAccess.onGrantDerived => GrantFieldMode.derived,
        AgentFieldAccess.onGrantRuntime => GrantFieldMode.runtime,
        _ => throw VaultPlaintextFormatException(
          'Field $id is not grant-authorized.',
        ),
      };
      if (!values.containsKey(id)) {
        throw VaultPlaintextFormatException('Unknown field $id.');
      }
      return ProjectedAgentField(
        id: id,
        kind: _grantKind(secret, id),
        mode: mode,
        value: values[id],
      );
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    return {
      'schema': 'palladin.grant-payload.v1',
      'entryType': secret.entryType.name,
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }

  /// Projects a decrypted wire-format MemberSecret without retaining a
  /// second typed copy of its secret values. Used by Grant refresh flows.
  static Map<String, Object?> grantPayloadFromJson(
    Map<String, dynamic> secret,
    Set<String> fieldIds,
  ) {
    final content = Map<String, dynamic>.from(secret['content'] as Map);
    final access = Map<String, dynamic>.from(secret['agentFieldAccess'] as Map);
    final entryType = secret['entryType'] as String;
    final custom = (content['customFields'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    final values = <String, Object?>{
      if (entryType == 'key') 'key.value': content['value'],
      if (entryType == 'credential') ...{
        'credential.username': content['username'],
        'credential.password': content['password'],
        'credential.url': content['url'],
        'credential.urlDomain': content['urlDomain'],
        'credential.totp': content['totp'],
      },
      if (entryType == 'script') ...{
        'script.source': content['source'],
        'script.interpreter': content['interpreter'],
        'script.refs': content['refs'],
      },
      if (entryType == 'creditCard') ...{
        for (final key in const [
          'cardholderName',
          'cardNumber',
          'expiryMonth',
          'expiryYear',
          'billingAddress',
        ])
          'creditCard.$key': content[key],
      },
      'notes': content['notes'],
      for (final field in custom)
        'custom:${field['id'] as String}': field['value'],
    };
    final fields =
        fieldIds.map((id) {
          final policy = access[id];
          final mode = switch (policy) {
            'onGrantValue' => 'value',
            'onGrantDerived' => 'derived',
            'onGrantRuntime' => 'runtime',
            _ => throw VaultPlaintextFormatException(
              '$id is not grant-authorized.',
            ),
          };
          if (!values.containsKey(id)) {
            throw VaultPlaintextFormatException('Unknown field $id.');
          }
          final kind = switch (id) {
            'key.value' ||
            'credential.password' ||
            'creditCard.cardNumber' => 'concealed',
            'credential.username' => 'text',
            'creditCard.cardholderName' ||
            'creditCard.expiryMonth' ||
            'creditCard.expiryYear' ||
            'creditCard.billingAddress' => 'text',
            'credential.url' => 'url',
            'credential.totp' => 'totp',
            'notes' => 'multiline',
            'script.source' => 'script',
            'script.interpreter' => 'interpreter',
            'script.refs' => 'refs',
            _ when id.startsWith('custom:') =>
              custom.singleWhere(
                    (field) => 'custom:${field['id'] as String}' == id,
                  )['kind']
                  as String,
            _ => throw VaultPlaintextFormatException(
              'Unknown grant field $id.',
            ),
          };
          return {'id': id, 'kind': kind, 'mode': mode, 'value': values[id]};
        }).toList()..sort(
          (left, right) =>
              (left['id'] as String).compareTo(right['id'] as String),
        );
    return {
      'schema': 'palladin.grant-payload.v1',
      'entryType': entryType,
      'fields': fields,
    };
  }

  static Map<String, Object?> _allValues(MemberSecret secret) => {
    'memberLabel': secret.memberLabel,
    'agentLabel': secret.agentLabel,
    'description': secret.description,
    'icon': secret.icon?.toJson(),
    'color': secret.color,
    'entryType': secret.entryType.name,
    ...secret.content.fieldValues(),
    for (final field in secret.content.customFields) field.fieldId: field.value,
  };

  static List<String> _capabilities(MemberSecret _) => const [
    'get',
    'exec',
    'inject',
  ];

  static String _grantKind(MemberSecret secret, String id) => switch (id) {
    'key.value' || 'credential.password' => 'concealed',
    'credential.username' => 'text',
    'credential.url' => 'url',
    'credential.totp' => 'totp',
    'creditCard.cardholderName' || 'creditCard.billingAddress' => 'text',
    'creditCard.cardNumber' => 'concealed',
    'creditCard.expiryMonth' || 'creditCard.expiryYear' => 'text',
    'notes' => 'multiline',
    'script.source' => 'script',
    'script.interpreter' => 'interpreter',
    'script.refs' => 'refs',
    _ when id.startsWith('custom:') =>
      secret.content.customFields
          .singleWhere((field) => field.fieldId == id)
          .kind,
    _ => throw VaultPlaintextFormatException('Unknown grant field $id.'),
  };
}

/// Produces deterministic UTF-8 JSON for the supported I-JSON subset.
Uint8List canonicalVaultJson(Map<String, Object?> value) {
  Object? canonicalize(Object? input) => switch (input) {
    Map<String, Object?> map =>
      SplayTreeMap<String, Object?>()..addEntries(
        map.entries.map(
          (entry) => MapEntry(entry.key, canonicalize(entry.value)),
        ),
      ),
    List<Object?> list => list.map(canonicalize).toList(growable: false),
    int() || String() || bool() || null => input,
    _ => throw const VaultPlaintextFormatException(
      'Only bounded integers and I-JSON values are supported.',
    ),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(canonicalize(value))));
}

Object? _required(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) {
    throw VaultPlaintextFormatException('Missing $key.');
  }
  return map[key];
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  throw VaultPlaintextFormatException('$name must be an object.');
}

void _exactKeys(Map<String, Object?> value, Set<String> keys, String name) {
  if (value.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(value.keys.toSet()).isNotEmpty) {
    throw VaultPlaintextFormatException('$name has an invalid field set.');
  }
}

void _schema(Map<String, Object?> map, String expected) {
  if (map['schema'] != expected) {
    throw VaultPlaintextFormatException('Expected schema $expected.');
  }
}

String _string(
  Object? value,
  String name, {
  required int min,
  required int max,
}) {
  if (value is! String || value.length < min || value.length > max) {
    throw VaultPlaintextFormatException('Invalid $name.');
  }
  return value;
}

int _integer(Object? value, String name, {required int min}) {
  if (value is! int || value < min) {
    throw VaultPlaintextFormatException('Invalid $name.');
  }
  return value;
}

String _publicAssetUrl(Object? value) {
  final text = _string(value, 'icon.url', min: 1, max: 2048);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw const VaultPlaintextFormatException('Invalid icon.url.');
  }
  return text;
}

String? _nullableString(
  Map<String, Object?> map,
  String key, {
  required int max,
}) {
  final value = _required(map, key);
  // Canonical web/backend plaintext contracts intentionally allow an empty
  // normalized string for nullable text projections produced by imports.
  return value == null ? null : _string(value, key, min: 0, max: max);
}

String? _color(Object? value) {
  if (value == null) return null;
  final color = _string(value, 'color', min: 7, max: 7);
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(color)) {
    throw const VaultPlaintextFormatException('Invalid color.');
  }
  return color;
}
