import 'dart:typed_data';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../domain/entities/entry_entity.dart';
import 'canonical_entry_detail_service.dart';
import 'entry_v2_crypto_service.dart';
import 'member_sync_service.dart';
import 'member_sync_session_authority_provider.dart';
import 'vault_rotation_crypto_service.dart';

/// Opens one complete local current Entry without invoking any Entry endpoint.
/// All plaintext and raw keys remain method-local and are wiped by the caller
/// snapshot lifecycle and the `finally` block below.
class LocalCurrentEntryService {
  const LocalCurrentEntryService({
    required LocalMemberEntryReader reader,
    required MemberSyncSessionAuthorityProvider authorityProvider,
    required VaultRotationCryptoService vaultKeys,
    required EntryV2CryptoService entryCrypto,
    required CanonicalEntryDetailService canonicalAdapter,
  }) : _reader = reader,
       _authorityProvider = authorityProvider,
       _vaultKeys = vaultKeys,
       _entryCrypto = entryCrypto,
       _canonicalAdapter = canonicalAdapter;

  final LocalMemberEntryReader _reader;
  final MemberSyncSessionAuthorityProvider _authorityProvider;
  final VaultRotationCryptoService _vaultKeys;
  final EntryV2CryptoService _entryCrypto;
  final CanonicalEntryDetailService _canonicalAdapter;

  Future<CanonicalEntrySnapshot> reveal({
    required EntryEntity expected,
    required Uint8List memberPrivateKey,
  }) => _reveal(
    vaultId: expected.vaultId,
    entryId: expected.id,
    memberPrivateKey: memberPrivateKey,
    expected: expected,
  );

  /// Opens by stable coordinates for shared reveal/copy/TOTP actions.
  Future<CanonicalEntrySnapshot> revealCurrent({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
  }) => _reveal(
    vaultId: vaultId,
    entryId: entryId,
    memberPrivateKey: memberPrivateKey,
  );

  Future<CanonicalEntrySnapshot> _reveal({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
    EntryEntity? expected,
  }) async {
    Uint8List? vaultKey;
    Map<String, dynamic>? canonical;
    try {
      final authority = await _authorityProvider.current();
      final material = await _reader.readCurrent(
        vaultId: vaultId,
        entryId: entryId,
        authority: authority,
      );
      if (material == null) {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.notFound,
        );
      }
      final item = material.item;
      if ((expected != null &&
              (item.currentRevision != expected.currentRevision ||
                  item.currentKeyVersion != expected.currentKeyVersion)) ||
          item.state != 'active') {
        throw const CanonicalEntryDetailException(
          CanonicalEntryDetailError.conflict,
        );
      }
      vaultKey = await _vaultKeys.openMemberVaultKey(
        material.memberVaultKey,
        memberPrivateKey,
        expectedOrganizationId: authority.organizationId,
        expectedVaultId: vaultId,
        expectedVaultKeyVersion: material.accessContext.vaultKeyVersion,
        expectedMemberKeyGeneration: material.accessContext.memberKeyGeneration,
      );
      canonical = await _entryCrypto.openMemberSecret(
        entryKey: item.entryKey!,
        memberSecret: item.memberSecret!,
        vaultKey: vaultKey,
      );
      final secret = _canonicalAdapter.adaptCanonicalSecret(canonical);
      final payload = secret['content'];
      if (payload is! Map) {
        throw const FormatException('Malformed local MemberSecret');
      }
      return CanonicalEntrySnapshot(
        entry: <String, dynamic>{
          'id': item.entryId,
          'organizationId': authority.organizationId,
          'vaultId': vaultId,
          'state': item.state,
          'updatedAt': item.updatedAt?.toIso8601String(),
          'currentRevision': item.currentRevision,
          'memberIndexRevision': item.memberIndexRevision,
          'currentKeyVersion': item.currentKeyVersion,
          'entryKey': item.entryKey,
          'memberSecret': item.memberSecret,
        },
        secret: secret,
        payload: Map<String, dynamic>.from(payload),
      );
    } on CanonicalEntryDetailException {
      rethrow;
    } on FormatException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } on EnvelopeException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.corrupt,
      );
    } finally {
      canonical?.clear();
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }
}
