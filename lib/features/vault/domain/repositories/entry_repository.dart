import 'dart:typed_data';

import '../entities/entry_entity.dart';

/// A revealed entry — metadata bundled with the decrypted payload.
///
/// Returned by [EntryRepository.revealEntry] so the UI can render the
/// reveal panel without making two passes through the data layer.
class RevealedEntry {
  const RevealedEntry({required this.entry, required this.payload});

  /// Domain metadata for the row (label, type, urlDomain, …).
  final EntryEntity entry;

  /// Decrypted payload as a JSON map. Callers should narrow to
  /// [KeyPayload] / [CredentialPayload] via the `type` field on
  /// [entry].
  final Map<String, dynamic> payload;
}

/// Domain contract for vault entry operations.
///
/// Implemented in the data layer by `EntryRepositoryImpl`. All
/// failures surface as `EntryException` with a typed `EntryErrorKind`
/// so the presentation layer can render localized messages.
abstract interface class EntryRepository {
  /// Returns every entry in the vault visible to the current user.
  /// Server-side ordering is preserved.
  Future<List<EntryEntity>> listEntries(String vaultId);

  /// Creates a new entry inside [vaultId] with a pre-encrypted payload.
  ///
  /// [encryptedBlob] and [nonce] must already be base64-encoded — the
  /// crypto step happens in `EntryCryptoService` and is the caller's
  /// responsibility.
  Future<EntryEntity> createEntry({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required String encryptedBlob,
    required String nonce,
    String? urlDomain,
  });

  /// Permanently deletes an entry.
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  });

  /// Fetches an entry's encrypted payload, unwraps the vault's VK with
  /// [privateKey], and returns the decrypted plaintext payload bundled
  /// with the entry metadata.
  ///
  /// [privateKey] must come from the unlocked auth state. The plaintext
  /// VK is held in memory only for the duration of this call and zeroed
  /// out before returning.
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
  });

  /// Encrypts [payloadJson] with the vault's VK (unwrapped from the
  /// server-stored sealed VK using [privateKey]) and persists it as a
  /// new entry. Convenience wrapper used by the Add Entry screen so the
  /// presentation layer never sees the plaintext VK.
  Future<EntryEntity> createEntryEncrypted({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
  });
}
