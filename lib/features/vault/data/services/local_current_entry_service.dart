import 'dart:typed_data';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../models/member_sync_models.dart';
import '../../domain/entities/entry_entity.dart';
import 'canonical_entry_detail_service.dart';
import 'entry_v2_crypto_service.dart';
import 'member_sync_service.dart';
import 'member_sync_session_authority_provider.dart';
import 'vault_rotation_crypto_service.dart';

/// A canonical plaintext snapshot paired with the independently authenticated
/// finite access context that authorized its local ciphertext generation.
final class LocalCurrentEntryReveal {
  const LocalCurrentEntryReveal({
    required this.snapshot,
    required this.accessContext,
  });

  final CanonicalEntrySnapshot snapshot;
  final MemberOfflineAccessContext accessContext;

  /// Clears all mutable plaintext maps owned by this reveal.
  void clear() => snapshot.clear();
}

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
  }) async => (await _reveal(
    vaultId: expected.vaultId,
    entryId: expected.id,
    memberPrivateKey: memberPrivateKey,
    expected: expected,
  )).snapshot;

  /// Opens by stable coordinates for shared reveal/copy/TOTP actions.
  Future<CanonicalEntrySnapshot> revealCurrent({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
  }) async => (await _reveal(
    vaultId: vaultId,
    entryId: entryId,
    memberPrivateKey: memberPrivateKey,
  )).snapshot;

  /// Opens the current Entry together with the cache-independent access
  /// authority required by native AutoFill manifest construction.
  Future<LocalCurrentEntryReveal> revealCurrentWithAuthority({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
  }) => _reveal(
    vaultId: vaultId,
    entryId: entryId,
    memberPrivateKey: memberPrivateKey,
  );

  Future<LocalCurrentEntryReveal> _reveal({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
    EntryEntity? expected,
  }) async {
    Uint8List? vaultKey;
    Map<String, dynamic>? canonical;
    Map<String, dynamic>? adaptedSecret;
    Map<String, dynamic>? adaptedPayload;
    var returningSnapshot = false;
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
      adaptedSecret = _canonicalAdapter.adaptCanonicalSecret(canonical);
      final payload = adaptedSecret['content'];
      if (payload is! Map) {
        throw const FormatException('Malformed local MemberSecret');
      }
      adaptedPayload = Map<String, dynamic>.from(payload);
      await _reader.revalidateCurrent(
        vaultId: vaultId,
        entryId: entryId,
        material: material,
        authority: authority,
      );
      returningSnapshot = true;
      return LocalCurrentEntryReveal(
        snapshot: CanonicalEntrySnapshot(
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
          secret: adaptedSecret,
          payload: adaptedPayload,
        ),
        accessContext: material.accessContext,
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
    } on LocalMemberEntryReadInvalidatedException {
      throw const CanonicalEntryDetailException(
        CanonicalEntryDetailError.conflict,
      );
    } finally {
      if (!returningSnapshot) {
        adaptedPayload?.clear();
        adaptedSecret?.clear();
      }
      canonical?.clear();
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }
}
