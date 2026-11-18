import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/vault_performance_budget.dart';
import 'member_sync_cache.dart';

enum MemberSearchIndexErrorKind { invalidIndex }

final class MemberSearchIndexException implements Exception {
  const MemberSearchIndexException();
  MemberSearchIndexErrorKind get kind =>
      MemberSearchIndexErrorKind.invalidIndex;
}

/// Unlocked metadata and authenticated reusable ciphertext; never retains keys.
final class MemberSearchIndexBundle {
  MemberSearchIndexBundle._(
    this.encoded,
    List<MemberIndexEntry> entries,
    this._scope,
    this._keyIdentity,
    List<String> chunks,
    List<String> hashes,
    this._manifestAad,
    this._manifestJson,
  ) : entries = List.unmodifiable(
        entries.map(
          (e) => MemberIndexEntry(
            entryId: e.entryId,
            entryType: e.entryType,
            memberLabel: e.memberLabel,
            searchFields: List.unmodifiable(e.searchFields),
            revision: e.revision,
            currentKeyVersion: e.currentKeyVersion,
            state: e.state,
            autofillDomains: List.unmodifiable(e.autofillDomains),
            iconReference: e.iconReference,
            username: e.username,
            corrupt: e.corrupt,
          ),
        ),
      ),
      _chunks = List.unmodifiable(chunks),
      _hashes = List.unmodifiable(hashes),
      _chunksJson = jsonEncode(chunks);

  MemberSearchIndexBundle._rebound(
    this.encoded,
    MemberSearchIndexBundle previous,
    this._manifestAad,
  ) : entries = previous.entries,
      _scope = previous._scope,
      _keyIdentity = previous._keyIdentity,
      _chunks = previous._chunks,
      _hashes = previous._hashes,
      _manifestJson = previous._manifestJson,
      _chunksJson = previous._chunksJson;
  final String encoded;
  final List<MemberIndexEntry> entries;
  final String _scope;
  final String _keyIdentity;
  final List<String> _chunks;
  final List<String> _hashes;
  final String _manifestAad;
  final String _manifestJson;
  final String _chunksJson;
}

/// Local ciphertext format, independent of the server's Entry envelopes.
/// The caller supplies authenticated stream state, never state from this file.
final class MemberSearchIndexCodec {
  MemberSearchIndexCodec({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;
  final Future<SodiumSumo> Function() _sodiumLoader;
  static const _bucketCount = 16;
  static const _maximumChunkBytes = 4 * 1024 * 1024;
  static const _maximumEncodedBytes = 90 * 1024 * 1024;
  static const _purpose = 'palladin.mobile.member-search-index.v1';

  /// The caller must independently establish unchanged stream content.
  /// Reuses authenticated chunks without traversing metadata or hashing them.
  Future<MemberSearchIndexBundle?> rebind({
    required MemberSearchIndexBundle previous,
    required MemberSyncCacheState state,
    required Uint8List vaultKey,
  }) async {
    _checkKey(vaultKey);
    if (previous._scope != _scope(state) ||
        previous._keyIdentity != _keyIdentity(vaultKey)) {
      return null;
    }
    final aad = _manifestAad(state);
    if (previous._manifestAad == aad) return previous;
    final sodium = await _sodiumLoader();
    final manifest = Uint8List.fromList(utf8.encode(previous._manifestJson));
    try {
      final encrypted = _encrypt(sodium, vaultKey, manifest, aad, 'manifest');
      final encoded =
          '{"version":1,"manifest":${jsonEncode(encrypted)},"chunks":${previous._chunksJson}}';
      return MemberSearchIndexBundle._rebound(encoded, previous, aad);
    } finally {
      manifest.fillRange(0, manifest.length, 0);
    }
  }

  Future<MemberSearchIndexBundle> seal({
    required List<MemberIndexEntry> entries,
    required MemberSyncCacheState state,
    required Uint8List vaultKey,
    MemberSearchIndexBundle? previous,
  }) async {
    _checkKey(vaultKey);
    if (entries.length > VaultPerformanceBudget.maximumIndexedEntries) {
      throw const MemberSearchIndexException();
    }
    final sodium = await _sodiumLoader();
    final scope = _scope(state);
    final identity = _keyIdentity(vaultKey);
    final buckets = List.generate(_bucketCount, (_) => <MemberIndexEntry>[]);
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.entryId)) throw const MemberSearchIndexException();
      buckets[_bucket(entry.entryId)].add(entry);
    }
    final chunks = <String>[];
    final hashes = <String>[];
    for (var i = 0; i < _bucketCount; i++) {
      buckets[i].sort((a, b) => a.entryId.compareTo(b.entryId));
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(buckets[i].map(_encodeEntry).toList())),
      );
      try {
        if (bytes.length > _maximumChunkBytes) {
          throw const MemberSearchIndexException();
        }
        final hash = sha256.convert(bytes).toString();
        hashes.add(hash);
        chunks.add(
          previous != null &&
                  previous._scope == scope &&
                  previous._keyIdentity == identity &&
                  previous._hashes[i] == hash
              ? previous._chunks[i]
              : _encrypt(sodium, vaultKey, bytes, _chunkAad(scope, i), 'chunk'),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({'digests': chunks.map(_ciphertextDigest).toList()}),
      ),
    );
    try {
      final encoded = jsonEncode({
        'version': 1,
        'manifest': _encrypt(
          sodium,
          vaultKey,
          manifest,
          _manifestAad(state),
          'manifest',
        ),
        'chunks': chunks,
      });
      if (encoded.length > _maximumEncodedBytes) {
        throw const MemberSearchIndexException();
      }
      return MemberSearchIndexBundle._(
        encoded,
        entries,
        scope,
        identity,
        chunks,
        hashes,
        _manifestAad(state),
        utf8.decode(manifest),
      );
    } finally {
      manifest.fillRange(0, manifest.length, 0);
    }
  }

  Future<MemberSearchIndexBundle> open({
    required String encoded,
    required MemberSyncCacheState state,
    required Uint8List vaultKey,
  }) async {
    _checkKey(vaultKey);
    if (encoded.length > _maximumEncodedBytes) {
      throw const MemberSearchIndexException();
    }
    final sodium = await _sodiumLoader();
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      if (value['version'] != 1) throw const MemberSearchIndexException();
      final chunks = List<String>.from(value['chunks'] as List);
      if (chunks.length != _bucketCount) {
        throw const MemberSearchIndexException();
      }
      final manifest = _decrypt(
        sodium,
        vaultKey,
        value['manifest'] as String,
        _manifestAad(state),
        'manifest',
        4096,
      );
      late List<String> digests;
      try {
        digests = List<String>.from(
          (jsonDecode(utf8.decode(manifest)) as Map)['digests'] as List,
        );
      } finally {
        manifest.fillRange(0, manifest.length, 0);
      }
      if (digests.length != _bucketCount) {
        throw const MemberSearchIndexException();
      }
      final entries = <MemberIndexEntry>[];
      final hashes = <String>[];
      final ids = <String>{};
      final scope = _scope(state);
      for (var i = 0; i < _bucketCount; i++) {
        if (_ciphertextDigest(chunks[i]) != digests[i]) {
          throw const MemberSearchIndexException();
        }
        final bytes = _decrypt(
          sodium,
          vaultKey,
          chunks[i],
          _chunkAad(scope, i),
          'chunk',
          _maximumChunkBytes,
        );
        try {
          hashes.add(sha256.convert(bytes).toString());
          final rows = jsonDecode(utf8.decode(bytes)) as List;
          if (entries.length + rows.length >
              VaultPerformanceBudget.maximumIndexedEntries) {
            throw const MemberSearchIndexException();
          }
          for (final row in rows) {
            final entry = _decodeEntry(row as Map<String, dynamic>);
            if (_bucket(entry.entryId) != i || !ids.add(entry.entryId)) {
              throw const MemberSearchIndexException();
            }
            entries.add(entry);
          }
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      return MemberSearchIndexBundle._(
        encoded,
        entries,
        scope,
        _keyIdentity(vaultKey),
        chunks,
        hashes,
        _manifestAad(state),
        jsonEncode({'digests': digests}),
      );
    } on MemberSearchIndexException {
      rethrow;
    } on Object {
      throw const MemberSearchIndexException();
    }
  }

  String _scope(MemberSyncCacheState state) {
    final context = state.accessContext.toJson()
      ..remove('issuedAt')
      ..remove('notAfter');
    return jsonEncode(context);
  }

  String _chunkAad(String scope, int bucket) =>
      jsonEncode([_purpose, 'chunk', scope, bucket]);
  String _manifestAad(MemberSyncCacheState state) => jsonEncode([
    _purpose,
    'manifest',
    state.sequence,
    state.accessContext.toJson(),
  ]);
  int _bucket(String id) =>
      sha256.convert(utf8.encode(id)).bytes.first % _bucketCount;
  String _ciphertextDigest(String ciphertext) =>
      sha256.convert(utf8.encode(ciphertext)).toString();
  void _checkKey(Uint8List key) {
    if (key.length != 32) throw const MemberSearchIndexException();
  }

  String _keyIdentity(Uint8List key) {
    final bytes = _derive(key, 'reuse-identity');
    try {
      return sha256.convert(bytes).toString();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Uint8List _derive(Uint8List key, String purpose) {
    final prk = Uint8List.fromList(
      Hmac(sha256, Uint8List(32)).convert(key).bytes,
    );
    try {
      return Uint8List.fromList(
        Hmac(
          sha256,
          prk,
        ).convert([...utf8.encode('$_purpose/$purpose'), 1]).bytes,
      );
    } finally {
      prk.fillRange(0, prk.length, 0);
    }
  }

  String _encrypt(
    SodiumSumo sodium,
    Uint8List vk,
    Uint8List plaintext,
    String aad,
    String purpose,
  ) {
    final derived = _derive(vk, purpose);
    SecureKey? key;
    try {
      key = SecureKey.fromList(sodium, derived);
      final nonce = sodium.randombytes.buf(24);
      final cipher = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: plaintext,
        nonce: nonce,
        key: key,
        additionalData: Uint8List.fromList(utf8.encode(aad)),
      );
      return base64Encode([...nonce, ...cipher]);
    } finally {
      key?.dispose();
      derived.fillRange(0, derived.length, 0);
    }
  }

  Uint8List _decrypt(
    SodiumSumo sodium,
    Uint8List vk,
    String encoded,
    String aad,
    String purpose,
    int maximumBytes,
  ) {
    if (encoded.length > ((maximumBytes + 40 + 2) ~/ 3) * 4) {
      throw const MemberSearchIndexException();
    }
    final bytes = base64Decode(encoded);
    if (bytes.length < 40 || bytes.length > maximumBytes + 40) {
      throw const MemberSearchIndexException();
    }
    final derived = _derive(vk, purpose);
    SecureKey? key;
    try {
      key = SecureKey.fromList(sodium, derived);
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: Uint8List.sublistView(bytes, 24),
        nonce: Uint8List.sublistView(bytes, 0, 24),
        key: key,
        additionalData: Uint8List.fromList(utf8.encode(aad)),
      );
    } finally {
      key?.dispose();
      derived.fillRange(0, derived.length, 0);
    }
  }

  Map<String, dynamic> _encodeEntry(MemberIndexEntry e) => {
    'entryId': e.entryId,
    'entryType': e.entryType,
    'memberLabel': e.memberLabel,
    'searchFields': e.searchFields,
    'revision': e.revision,
    'currentKeyVersion': e.currentKeyVersion,
    'state': e.state.name,
    'autofillDomains': e.autofillDomains,
    'iconReference': e.iconReference,
    'username': e.username,
    'corrupt': e.corrupt,
  };
  MemberIndexEntry _decodeEntry(Map<String, dynamic> e) => MemberIndexEntry(
    entryId: e['entryId'] as String,
    entryType: e['entryType'] as int,
    memberLabel: e['memberLabel'] as String,
    searchFields: List<String>.unmodifiable(e['searchFields'] as List),
    revision: e['revision'] as String,
    currentKeyVersion: e['currentKeyVersion'] as int,
    state: MemberEntryState.values.byName(e['state'] as String),
    autofillDomains: List<String>.unmodifiable(e['autofillDomains'] as List),
    iconReference: e['iconReference'] as String?,
    username: e['username'] as String?,
    corrupt: e['corrupt'] as bool,
  );
}
