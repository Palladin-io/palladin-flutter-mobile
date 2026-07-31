/// Domain contract for Vault mutations that do not open encrypted metadata.
///
/// Implemented in the data layer by `VaultRepositoryImpl`. All
/// failures surface as `VaultException` with a typed `VaultErrorKind`
/// so the presentation layer can render localized error messages
/// without leaking transport details.
abstract interface class VaultRepository {
  /// Permanently deletes a vault. The backend cascades the delete to
  /// all entries and grants.
  Future<void> deleteVault(String id);
}
