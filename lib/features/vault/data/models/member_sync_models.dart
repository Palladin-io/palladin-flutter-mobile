/// Opaque protocol-2 Member projection returned by snapshot and delta sync.
final class MemberSyncItemModel {
  const MemberSyncItemModel({
    required this.entryId,
    required this.kind,
    this.state,
    this.currentRevision,
    this.memberIndexRevision,
    this.currentKeyVersion,
    this.entryKey,
    this.memberIndex,
  });

  factory MemberSyncItemModel.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    final entryId = json['entryId'];
    if (entryId is! String || (kind != 'head' && kind != 'tombstone')) {
      throw const FormatException('Malformed Member sync item');
    }
    if (kind == 'tombstone') {
      return MemberSyncItemModel(entryId: entryId, kind: kind as String);
    }
    final entryKey = json['entryKey'];
    final memberIndex = json['memberIndex'];
    final state = json['state'];
    const validStates = {
      'active',
      'Active',
      'archived',
      'Archived',
      'deleted',
      'Deleted',
      0,
      1,
      2,
      3,
    };
    if (entryKey is! Map ||
        memberIndex is! Map ||
        !validStates.contains(state)) {
      throw const FormatException('Member head has no encrypted projection');
    }
    return MemberSyncItemModel(
      entryId: entryId,
      kind: kind as String,
      state: state,
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
    );
  }

  final String entryId;
  final String kind;
  final Object? state;
  final String? currentRevision;
  final String? memberIndexRevision;
  final int? currentKeyVersion;
  final Map<String, dynamic>? entryKey;
  final Map<String, dynamic>? memberIndex;

  bool get isTombstone => kind == 'tombstone';

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'kind': kind,
    if (state != null) 'state': state,
    if (currentRevision != null) 'currentRevision': currentRevision,
    if (memberIndexRevision != null) 'memberIndexRevision': memberIndexRevision,
    if (currentKeyVersion != null) 'currentKeyVersion': currentKeyVersion,
    if (entryKey != null) 'entryKey': entryKey,
    if (memberIndex != null) 'memberIndex': memberIndex,
  };
}

/// One page of a stable Member snapshot.
final class MemberSnapshotPage {
  const MemberSnapshotPage({
    required this.snapshotBaseSequence,
    required this.items,
    this.nextCursor,
  });

  factory MemberSnapshotPage.fromJson(Map<String, dynamic> json) =>
      MemberSnapshotPage(
        snapshotBaseSequence: _decimal(
          json['snapshotBaseSequence'],
          'snapshotBaseSequence',
        ),
        items: _items(json['items']),
        nextCursor: _nullableString(json['nextCursor'], 'nextCursor'),
      );

  final String snapshotBaseSequence;
  final List<MemberSyncItemModel> items;
  final String? nextCursor;
}

/// One page of a bounded Member delta.
final class MemberDeltaPage {
  const MemberDeltaPage({
    required this.deltaUpperBound,
    required this.appliedThroughSequence,
    required this.items,
    this.continuationCursor,
  });

  factory MemberDeltaPage.fromJson(Map<String, dynamic> json) =>
      MemberDeltaPage(
        deltaUpperBound: _decimal(json['deltaUpperBound'], 'deltaUpperBound'),
        appliedThroughSequence: _decimal(
          json['appliedThroughSequence'],
          'appliedThroughSequence',
        ),
        items: _items(json['items']),
        continuationCursor: _nullableString(
          json['continuationCursor'],
          'continuationCursor',
        ),
      );

  final String deltaUpperBound;
  final String appliedThroughSequence;
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
    if (json['outcome'] != 'resetRequired' ||
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
  if (value is! String || !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value)) {
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

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

List<MemberSyncItemModel> _items(Object? value) {
  if (value is! List || value.length > 200) {
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
