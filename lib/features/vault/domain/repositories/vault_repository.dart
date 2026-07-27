import 'dart:typed_data';

import '../entities/vault_entity.dart';

/// Domain contract for vault CRUD operations.
///
/// Implemented in the data layer by `VaultRepositoryImpl`. All
/// failures surface as `VaultException` with a typed `VaultErrorKind`
/// so the presentation layer can render localized error messages
/// without leaking transport details.
abstract interface class VaultRepository {
  /// Returns every vault visible to the current user. Server-side
  /// ordering is preserved.
  Future<List<VaultEntity>> listVaults();

  /// Fetches a single vault by id, including its summary counters.
  Future<VaultEntity> getVault(String id);

  /// Creates a new vault with the supplied metadata and a pre-wrapped
  /// vault key.
  ///
  /// [wrappedVK] is the base64-encoded sealed-box ciphertext containing
  /// the freshly generated 32-byte vault key, sealed for the user's
  /// X25519 public key. The crypto step happens in `VaultCryptoService`
  /// and is the caller's responsibility — the repository merely ships
  /// the bytes to the backend.
  Future<VaultEntity> createVault({
    required String name,
    String? description,
    String? icon,
    String? color,
    required GrantMode grantMode,
    required Uint8List privateKey,
  });

  /// Patch-updates a vault. Only the supplied (non-null) fields are
  /// sent — all others are left untouched on the server.
  Future<void> updateVault(
    String id, {
    String? name,
    String? description,
    String? icon,
    String? color,
    GrantMode? grantMode,
  });

  /// Permanently deletes a vault. The backend cascades the delete to
  /// all entries and grants.
  Future<void> deleteVault(String id);
}
