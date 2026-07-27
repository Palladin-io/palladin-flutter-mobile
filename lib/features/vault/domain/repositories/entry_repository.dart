import 'dart:typed_data';

import '../entities/custom_field.dart';
import '../entities/entry_entity.dart';
import '../entities/import_draft.dart';

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

  /// Permanently deletes an entry.
  Future<void> deleteEntry({required String vaultId, required String entryId});

  /// Fetches an entry's encrypted payload, unwraps the vault's VK with
  /// [privateKey], and returns the decrypted plaintext payload bundled
  /// with the entry metadata.
  ///
  /// [privateKey] must come from the unlocked auth state. The plaintext
  /// VK is held in memory only for the duration of this call and zeroed
  /// out before returning.
  ///
  /// [wrappedVK] is the base64 sealed VK (as returned by
  /// `GET /api/vaults/{id}`). When the caller already holds it from the
  /// vault detail load, threading it through here avoids a redundant
  /// `GET /api/vaults/{id}` call. When `null`, the implementation
  /// fetches it on demand.
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
    String? wrappedVK,
  });

  /// Encrypts [payloadJson] with the vault's VK (unwrapped from the
  /// server-stored sealed VK using [privateKey]) and persists it as a
  /// new entry. Convenience wrapper used by the Add Entry screen so the
  /// presentation layer never sees the plaintext VK.
  ///
  /// [wrappedVK] mirrors the same parameter on [revealEntry] — when
  /// provided, the implementation skips the extra `GET /api/vaults/{id}`
  /// round-trip.
  Future<EntryEntity> createEntryEncrypted({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    List<AgentField>? agentFields,
  });

  /// Re-encrypts [payload] with the vault's VK and PUTs the update to
  /// `/api/vaults/{vaultId}/entries/{entryId}`. Returns the updated
  /// [EntryEntity] (constructed locally — the backend returns 204).
  ///
  /// [createdAt] must be the entry's original creation timestamp — PUT
  /// returns 204 so we cannot read it back from the server, and inventing
  /// a new `DateTime.now()` here would overwrite the real value on every
  /// edit. Pass the timestamp from the entity in the parent list.
  ///
  /// [wrappedVK] mirrors the same parameter on [revealEntry].
  Future<EntryEntity> updateEntryEncrypted({
    required String vaultId,
    required String entryId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    required DateTime createdAt,
    List<AgentField>? agentFields,
  });

  /// Bulk-imports entries into [vaultId]. The vault's VK is unwrapped
  /// exactly once, then every draft payload is encrypted with it before
  /// the ciphertext is shipped — no plaintext VK crosses the data-layer
  /// boundary and the key bytes are zeroed in `finally`.
  ///
  /// [creates] are POSTed to the bulk import endpoint in chunks of at most
  /// [chunkSize] (backend limit 500). [overwrites] target existing entries
  /// via individual PUTs. [onProgress] fires after each unit of work
  /// (`done` out of `total`) so the wizard can render a progress bar.
  ///
  /// [format] is the stable source-format id recorded by the backend.
  Future<ImportResult> importEntriesEncrypted({
    required String vaultId,
    required String format,
    required List<ImportEntryDraft> creates,
    required List<ImportEntryOverwrite> overwrites,
    required Uint8List privateKey,
    String? wrappedVK,
    int chunkSize,
    void Function(int done, int total)? onProgress,
  });

  /// Reveals only domain-addressable `CREDENTIAL` entries for the native
  /// system AutoFill cache. Entries without a usable domain and all KEY /
  /// SCRIPT payloads are skipped before their encrypted detail is fetched.
  Future<List<RevealedEntry>> revealAutoFillCredentials({
    required String vaultId,
    required Uint8List privateKey,
    String? wrappedVK,
  });
}
