import 'dart:collection';
import 'dart:typed_data';

/// Structural Vault key epoch associated with an unlocked Vault key.
final class VaultKeyEpoch {
  const VaultKeyEpoch({
    required this.vaultKeyVersion,
    required this.vdkVersion,
    required this.agentMessageKeyVersion,
    required this.manifestSigningKeyVersion,
  });
  final int vaultKeyVersion;
  final int vdkVersion;
  final int agentMessageKeyVersion;
  final int manifestSigningKeyVersion;
  bool get isValid =>
      vaultKeyVersion > 0 &&
      vdkVersion > 0 &&
      agentMessageKeyVersion > 0 &&
      manifestSigningKeyVersion > 0;
}

/// Non-secret metadata binding a wrapped VK to its recipient key.
final class MemberVaultKeyWrapperMetadata {
  const MemberVaultKeyWrapperMetadata({
    required this.wrapperSuiteId,
    required this.wrappedKeyVersion,
    required this.memberKeyGeneration,
    required this.recipientKeyVersion,
    required this.recipientFingerprint,
  });
  final String wrapperSuiteId;
  final int wrappedKeyVersion;
  final int memberKeyGeneration;
  final int recipientKeyVersion;
  final String recipientFingerprint;
  bool get isValid =>
      wrapperSuiteId.isNotEmpty &&
      wrappedKeyVersion > 0 &&
      memberKeyGeneration > 0 &&
      recipientKeyVersion > 0 &&
      recipientFingerprint.isNotEmpty;
}

/// Raw key material retained only for the lifetime of an unlocked session.
final class UnlockedVaultSession {
  UnlockedVaultSession({
    required this.organizationId,
    required this.vaultId,
    required Uint8List vaultKey,
    Uint8List? vaultDiscoveryKey,
    required this.epoch,
    required this.memberKeyGeneration,
    required this.wrapper,
  }) : _vaultKey = Uint8List.fromList(vaultKey),
       _vaultDiscoveryKey = vaultDiscoveryKey == null
           ? null
           : Uint8List.fromList(vaultDiscoveryKey) {
    if (organizationId.isEmpty ||
        vaultId.isEmpty ||
        _vaultKey.length != 32 ||
        (_vaultDiscoveryKey != null && _vaultDiscoveryKey.length != 32) ||
        !epoch.isValid ||
        memberKeyGeneration <= 0 ||
        !wrapper.isValid ||
        wrapper.wrappedKeyVersion != epoch.vaultKeyVersion ||
        wrapper.memberKeyGeneration != memberKeyGeneration) {
      _vaultKey.fillRange(0, _vaultKey.length, 0);
      _vaultDiscoveryKey?.fillRange(0, _vaultDiscoveryKey.length, 0);
      throw ArgumentError('Invalid unlocked Vault session material.');
    }
  }
  final String organizationId;
  final String vaultId;
  final VaultKeyEpoch epoch;
  final int memberKeyGeneration;
  final MemberVaultKeyWrapperMetadata wrapper;
  final Uint8List _vaultKey;
  final Uint8List? _vaultDiscoveryKey;
  bool _disposed = false;
  Uint8List copyVaultKey() {
    if (_disposed) throw StateError('Vault session has been disposed.');
    return Uint8List.fromList(_vaultKey);
  }

  Uint8List copyVaultDiscoveryKey() {
    if (_disposed) throw StateError('Vault session has been disposed.');
    final value = _vaultDiscoveryKey;
    if (value == null) {
      throw StateError('Vault discovery key is not unlocked.');
    }
    return Uint8List.fromList(value);
  }

  void dispose() {
    if (_disposed) return;
    _vaultKey.fillRange(0, _vaultKey.length, 0);
    _vaultDiscoveryKey?.fillRange(0, _vaultDiscoveryKey.length, 0);
    _disposed = true;
  }
}

/// Process-memory-only registry for unlocked Vault sessions.
final class VaultSessionStore {
  final Map<String, UnlockedVaultSession> _sessions = {};
  Uint8List? _memberPrivateKey;
  int _memberKeySessionGeneration = 0;

  /// Monotonic guard for async work derived from the in-memory Member key.
  int get memberKeySessionGeneration => _memberKeySessionGeneration;

  void setMemberPrivateKey(Uint8List value) {
    if (value.length != 32) throw ArgumentError('Invalid member private key.');
    final replacement = Uint8List.fromList(value);
    _memberPrivateKey?.fillRange(0, _memberPrivateKey!.length, 0);
    _memberPrivateKey = replacement;
    _memberKeySessionGeneration++;
  }

  Uint8List copyMemberPrivateKey() {
    final value = _memberPrivateKey;
    if (value == null) throw StateError('Member key is not unlocked.');
    return Uint8List.fromList(value);
  }

  UnmodifiableListView<String> get unlockedVaultIds =>
      UnmodifiableListView(_sessions.keys);
  bool contains(String vaultId) => _sessions.containsKey(vaultId);
  Uint8List copyVaultKey({
    required String organizationId,
    required String vaultId,
  }) {
    final session = _sessions[vaultId];
    if (session == null || session.organizationId != organizationId) {
      throw StateError('Vault is not unlocked for this organization.');
    }
    return session.copyVaultKey();
  }

  Uint8List copyVaultDiscoveryKey({
    required String organizationId,
    required String vaultId,
  }) {
    final session = _sessions[vaultId];
    if (session == null || session.organizationId != organizationId) {
      throw StateError('Vault is not unlocked for this organization.');
    }
    return session.copyVaultDiscoveryKey();
  }

  UnlockedVaultSession session(String vaultId) {
    final value = _sessions[vaultId];
    if (value == null) throw StateError('Vault is not unlocked.');
    return value;
  }

  void install({
    required String organizationId,
    required String vaultId,
    required Uint8List vaultKey,
    Uint8List? vaultDiscoveryKey,
    required VaultKeyEpoch epoch,
    required int memberKeyGeneration,
    required MemberVaultKeyWrapperMetadata wrapper,
  }) {
    final candidate = UnlockedVaultSession(
      organizationId: organizationId,
      vaultId: vaultId,
      vaultKey: vaultKey,
      vaultDiscoveryKey: vaultDiscoveryKey,
      epoch: epoch,
      memberKeyGeneration: memberKeyGeneration,
      wrapper: wrapper,
    );
    final previous = _sessions[vaultId];
    _sessions[vaultId] = candidate;
    previous?.dispose();
  }

  void remove(String vaultId) => _sessions.remove(vaultId)?.dispose();
  void clear() {
    _memberKeySessionGeneration++;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      session.dispose();
    }
    _memberPrivateKey?.fillRange(0, _memberPrivateKey!.length, 0);
    _memberPrivateKey = null;
  }
}
