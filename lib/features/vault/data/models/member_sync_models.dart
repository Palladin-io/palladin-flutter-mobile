/// Authenticated finite authority attached to every policy-2 sync page.
final class MemberOfflineAccessContext {
  const MemberOfflineAccessContext({
    required this.contextVersion,
    required this.principalId,
    required this.organizationId,
    required this.organizationMembershipGeneration,
    required this.vaultId,
    required this.memberId,
    required this.memberKeyGeneration,
    required this.vaultKeyVersion,
    required this.memberRecipientKeyVersion,
    required this.memberRecipientKeyFingerprint,
    required this.offlinePolicy,
    required this.offlinePolicyVersion,
    required this.issuedAt,
    required this.notAfter,
  });

  factory MemberOfflineAccessContext.fromJson(Map<String, dynamic> json) {
    const fields = {
      'contextVersion',
      'principalId',
      'organizationId',
      'organizationMembershipGeneration',
      'vaultId',
      'memberId',
      'memberKeyGeneration',
      'vaultKeyVersion',
      'memberRecipientKeyVersion',
      'memberRecipientKeyFingerprint',
      'offlinePolicy',
      'offlinePolicyVersion',
      'issuedAt',
      'notAfter',
    };
    final policy = json['offlinePolicy'];
    if (!_hasExactKeys(json, fields) ||
        json['contextVersion'] != 1 ||
        policy is! String ||
        !const {'disabled', '1h', '4h', '24h'}.contains(policy)) {
      throw const FormatException('Unsupported Member access context');
    }
    return MemberOfflineAccessContext(
      contextVersion: 1,
      principalId: _uuid(json['principalId'], 'principalId'),
      organizationId: _uuid(json['organizationId'], 'organizationId'),
      organizationMembershipGeneration: _decimal(
        json['organizationMembershipGeneration'],
        'organizationMembershipGeneration',
      ),
      vaultId: _uuid(json['vaultId'], 'vaultId'),
      memberId: _uuid(json['memberId'], 'memberId'),
      memberKeyGeneration: _positiveInt(
        json['memberKeyGeneration'],
        'memberKeyGeneration',
      ),
      vaultKeyVersion: _positiveInt(json['vaultKeyVersion'], 'vaultKeyVersion'),
      memberRecipientKeyVersion: _positiveInt(
        json['memberRecipientKeyVersion'],
        'memberRecipientKeyVersion',
      ),
      memberRecipientKeyFingerprint: _requiredString(
        json['memberRecipientKeyFingerprint'],
        'memberRecipientKeyFingerprint',
      ),
      offlinePolicy: policy,
      offlinePolicyVersion: _positiveInt(
        json['offlinePolicyVersion'],
        'offlinePolicyVersion',
      ),
      issuedAt: _instant(json['issuedAt'], 'issuedAt'),
      notAfter: _instant(json['notAfter'], 'notAfter'),
    );
  }

  final int contextVersion;
  final String principalId;
  final String organizationId;
  final String organizationMembershipGeneration;
  final String vaultId;
  final String memberId;
  final int memberKeyGeneration;
  final int vaultKeyVersion;
  final int memberRecipientKeyVersion;
  final String memberRecipientKeyFingerprint;
  final String offlinePolicy;
  final int offlinePolicyVersion;
  final DateTime issuedAt;
  final DateTime notAfter;

  Duration get leaseDuration => switch (offlinePolicy) {
    'disabled' => Duration.zero,
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '24h' => const Duration(hours: 24),
    _ => throw const FormatException('Unsupported offline policy'),
  };

  Map<String, dynamic> toJson() => {
    'contextVersion': contextVersion,
    'principalId': principalId,
    'organizationId': organizationId,
    'organizationMembershipGeneration': organizationMembershipGeneration,
    'vaultId': vaultId,
    'memberId': memberId,
    'memberKeyGeneration': memberKeyGeneration,
    'vaultKeyVersion': vaultKeyVersion,
    'memberRecipientKeyVersion': memberRecipientKeyVersion,
    'memberRecipientKeyFingerprint': memberRecipientKeyFingerprint,
    'offlinePolicy': offlinePolicy,
    'offlinePolicyVersion': offlinePolicyVersion,
    'issuedAt': _formatInstant(issuedAt),
    'notAfter': _formatInstant(notAfter),
  };
}

/// Complete opaque current Entry material returned by snapshot and delta sync.
final class MemberSyncItemModel {
  const MemberSyncItemModel({
    required this.entryId,
    required this.kind,
    required this.updatedAt,
    this.state,
    this.currentRevision,
    this.memberIndexRevision,
    this.currentKeyVersion,
    this.entryKey,
    this.memberIndex,
    this.memberSecret,
  });

  factory MemberSyncItemModel.fromJson(Map<String, dynamic> json) {
    const requiredFields = {
      'entryId',
      'kind',
      'state',
      'updatedAt',
      'currentRevision',
      'memberIndexRevision',
      'currentKeyVersion',
      'entryKey',
      'memberIndex',
      'memberSecret',
    };
    if (!_hasExactKeys(json, requiredFields)) {
      throw const FormatException('Incomplete Member sync item');
    }
    final kind = json['kind'];
    final entryId = _uuid(json['entryId'], 'entryId');
    if (kind != 'head' && kind != 'tombstone') {
      throw const FormatException('Malformed Member sync item');
    }
    if (kind == 'tombstone') {
      if (requiredFields
          .difference(const {'entryId', 'kind'})
          .any((field) => json[field] != null)) {
        throw const FormatException('Tombstone carries Entry material');
      }
      return MemberSyncItemModel(
        entryId: entryId,
        kind: kind as String,
        updatedAt: null,
      );
    }
    final entryKey = json['entryKey'];
    final memberIndex = json['memberIndex'];
    final memberSecret = json['memberSecret'];
    final state = json['state'];
    if (entryKey is! Map ||
        memberIndex is! Map ||
        memberSecret is! Map ||
        !const {'active', 'archived', 'deleted'}.contains(state)) {
      throw const FormatException('Member head has no complete material');
    }
    return MemberSyncItemModel(
      entryId: entryId,
      kind: kind as String,
      state: state,
      updatedAt: _instant(json['updatedAt'], 'updatedAt'),
      currentRevision: _decimal(json['currentRevision'], 'currentRevision'),
      memberIndexRevision: _decimal(
        json['memberIndexRevision'],
        'memberIndexRevision',
      ),
      currentKeyVersion: _positiveInt(
        json['currentKeyVersion'],
        'currentKeyVersion',
      ),
      entryKey: Map<String, dynamic>.from(entryKey),
      memberIndex: Map<String, dynamic>.from(memberIndex),
      memberSecret: Map<String, dynamic>.from(memberSecret),
    );
  }

  final String entryId;
  final String kind;
  final String? state;
  final DateTime? updatedAt;
  final String? currentRevision;
  final String? memberIndexRevision;
  final int? currentKeyVersion;
  final Map<String, dynamic>? entryKey;
  final Map<String, dynamic>? memberIndex;
  final Map<String, dynamic>? memberSecret;

  bool get isTombstone => kind == 'tombstone';

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'kind': kind,
    'state': state,
    'updatedAt': updatedAt == null ? null : _formatInstant(updatedAt!),
    'currentRevision': currentRevision,
    'memberIndexRevision': memberIndexRevision,
    'currentKeyVersion': currentKeyVersion,
    'entryKey': entryKey,
    'memberIndex': memberIndex,
    'memberSecret': memberSecret,
  };
}

/// One page of a stable Member snapshot.
final class MemberSnapshotPage {
  const MemberSnapshotPage({
    required this.snapshotBaseSequence,
    required this.accessContext,
    required this.memberVaultKey,
    required this.items,
    this.nextCursor,
  });

  factory MemberSnapshotPage.fromJson(Map<String, dynamic> json) {
    const fields = {
      'snapshotBaseSequence',
      'accessContext',
      'memberVaultKey',
      'items',
      'nextCursor',
    };
    if (!_hasExactKeys(json, fields)) {
      throw const FormatException('Snapshot cursor field is missing');
    }
    return MemberSnapshotPage(
      snapshotBaseSequence: _decimal(
        json['snapshotBaseSequence'],
        'snapshotBaseSequence',
      ),
      accessContext: MemberOfflineAccessContext.fromJson(
        _map(json['accessContext'], 'accessContext'),
      ),
      memberVaultKey: _map(json['memberVaultKey'], 'memberVaultKey'),
      items: _items(json['items']),
      nextCursor: _nullableString(json['nextCursor'], 'nextCursor'),
    );
  }

  final String snapshotBaseSequence;
  final MemberOfflineAccessContext accessContext;
  final Map<String, dynamic> memberVaultKey;
  final List<MemberSyncItemModel> items;
  final String? nextCursor;
}

/// One page of a bounded Member delta.
final class MemberDeltaPage {
  const MemberDeltaPage({
    required this.deltaUpperBound,
    required this.appliedThroughSequence,
    required this.accessContext,
    required this.memberVaultKey,
    required this.items,
    this.continuationCursor,
  });

  factory MemberDeltaPage.fromJson(Map<String, dynamic> json) {
    const fields = {
      'deltaUpperBound',
      'appliedThroughSequence',
      'accessContext',
      'memberVaultKey',
      'items',
      'continuationCursor',
    };
    if (!_hasExactKeys(json, fields)) {
      throw const FormatException('Delta cursor field is missing');
    }
    return MemberDeltaPage(
      deltaUpperBound: _decimal(json['deltaUpperBound'], 'deltaUpperBound'),
      appliedThroughSequence: _decimal(
        json['appliedThroughSequence'],
        'appliedThroughSequence',
      ),
      accessContext: MemberOfflineAccessContext.fromJson(
        _map(json['accessContext'], 'accessContext'),
      ),
      memberVaultKey: _map(json['memberVaultKey'], 'memberVaultKey'),
      items: _items(json['items']),
      continuationCursor: _nullableString(
        json['continuationCursor'],
        'continuationCursor',
      ),
    );
  }

  final String deltaUpperBound;
  final String appliedThroughSequence;
  final MemberOfflineAccessContext accessContext;
  final Map<String, dynamic> memberVaultKey;
  final List<MemberSyncItemModel> items;
  final String? continuationCursor;
}

/// Server instruction that local incremental state is outside retention.
final class MemberSyncReset {
  const MemberSyncReset({
    required this.currentSequence,
    required this.minRetainedSequence,
  });

  factory MemberSyncReset.fromJson(Map<String, dynamic> json) {
    const fields = {
      'outcome',
      'currentSequence',
      'minRetainedSequence',
      'newSnapshotRequired',
    };
    if (!_hasExactKeys(json, fields) ||
        json['outcome'] != 'resetRequired' ||
        json['newSnapshotRequired'] != true) {
      throw const FormatException('Malformed Member sync reset response');
    }
    return MemberSyncReset(
      currentSequence: _decimal(json['currentSequence'], 'currentSequence'),
      minRetainedSequence: _decimal(
        json['minRetainedSequence'],
        'minRetainedSequence',
      ),
    );
  }

  final String currentSequence;
  final String minRetainedSequence;
}

String _decimal(Object? value, String field) {
  const maximumUint64 = '18446744073709551615';
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,19})$').hasMatch(value) ||
      (value.length == maximumUint64.length &&
          value.compareTo(maximumUint64) > 0)) {
    throw FormatException('$field must be an unsigned decimal string');
  }
  return value;
}

int _positiveInt(Object? value, String field) {
  if (value is! int || value < 1 || value > 0xffffffff) {
    throw FormatException('$field must be a positive uint32');
  }
  return value;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String _uuid(Object? value, String field) {
  final text = _requiredString(value, field);
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(text)) {
    throw FormatException('$field must be a canonical UUID');
  }
  return text;
}

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  final text = _requiredString(value, field);
  if (text.length > 2048) {
    throw FormatException('$field exceeds the cursor limit');
  }
  return text;
}

bool _hasExactKeys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

DateTime _instant(Object? value, String field) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$',
      ).hasMatch(value)) {
    throw FormatException('$field must be a canonical UTC instant');
  }
  return DateTime.parse(value).toUtc();
}

String _formatInstant(DateTime value) =>
    value.toUtc().toIso8601String().replaceFirst(RegExp(r'\.000Z$'), 'Z');

Map<String, dynamic> _map(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, dynamic>.from(value);
}

List<MemberSyncItemModel> _items(Object? value) {
  if (value is! List ||
      value.length > 200 ||
      value.any((item) => item is! Map)) {
    throw const FormatException('Member sync page exceeds item limit');
  }
  return value
      .map(
        (item) => MemberSyncItemModel.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      )
      .toList(growable: false);
}
