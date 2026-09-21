import '../../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../../core/crypto/x25519_key_wrapper.dart';
import '../../../domain/entities/entry_share_copy.dart';
import '../../../domain/entities/entry_share_list.dart';

final class EntryShareCopyVaultAuthority {
  const EntryShareCopyVaultAuthority._(
    this.vaultKeyVersion,
    this.vdkVersion,
    this.memberKeyGeneration,
  );
  final int vaultKeyVersion, vdkVersion, memberKeyGeneration;

  static EntryShareCopyVaultAuthority read(
    Map<String, dynamic> vault,
    String selectedVaultId,
    EntrySharingSession owner,
  ) {
    if (vault['id'] != selectedVaultId ||
        vault['organizationId'] != owner.organizationId ||
        vault['metadataRevision'] is! String) {
      throw const EntryShareCopyException(EntryShareCopyError.invalidAuthority);
    }
    return _read(
      vault,
      selectedVaultId,
      owner,
      metadataRevision: vault['metadataRevision'],
    );
  }

  static EntryShareCopyVaultAuthority readSummary(
    Map<String, dynamic> vault,
    EntrySharingSession owner,
  ) => _read(vault, vault['id'] as String, owner);

  static EntryShareCopyVaultAuthority _read(
    Map<String, dynamic> vault,
    String selectedVaultId,
    EntrySharingSession owner, {
    Object? metadataRevision,
  }) {
    const invalid = EntryShareCopyException(
      EntryShareCopyError.invalidAuthority,
    );
    try {
      final epoch = vault['currentKeyEpoch'] as Map;
      final vkVersion = epoch['vaultKeyVersion'] as int;
      final vdkVersion = epoch['vdkVersion'] as int;
      final generation = vault['memberKeyGeneration'] as int;
      final wrapper =
          ((vault['memberVaultKey'] as Map)['wrappedVaultKey']
                  as Map)['descriptor']
              as Map;
      _scope(wrapper['scope'] as Map, selectedVaultId, owner, member: true);
      if (wrapper['protocolVersion'] != 2 ||
          wrapper['wrapperSuiteId'] !=
              RecipientWrapperSuiteId.x25519SealedBoxV1.wireValue ||
          WrapperPurpose.parseWire(wrapper['purpose']) !=
              WrapperPurpose.memberVaultKey ||
          wrapper['wrappedKeyVersion'] != vkVersion ||
          wrapper['memberKeyGeneration'] != generation ||
          wrapper['parentDescriptorHash'] != null) {
        throw invalid;
      }
      for (final (field, purpose, version) in [
        ('memberVaultMetadata', EnvelopePurpose.memberVaultMetadata, vkVersion),
        ('discoveryKey', EnvelopePurpose.vaultDiscoveryKeyByVk, vdkVersion),
      ]) {
        final descriptor = (vault[field] as Map)['descriptor'] as Map;
        _scope(descriptor['scope'] as Map, selectedVaultId, owner);
        if (descriptor['protocolVersion'] != 2 ||
            descriptor['cryptoSuiteId'] !=
                CryptoSuiteId.palladinVaultXChaChaV1.wireValue ||
            EnvelopePurpose.parseWire(descriptor['purpose']) != purpose ||
            descriptor['keyVersion'] != version ||
            descriptor['memberKeyGeneration'] != generation) {
          throw invalid;
        }
        if (field == 'memberVaultMetadata' &&
            metadataRevision != null &&
            descriptor['resourceRevision'] != metadataRevision) {
          throw invalid;
        }
        if (field == 'discoveryKey' &&
            (descriptor['binding'] as Map)['wrappingVaultKeyVersion'] !=
                vkVersion) {
          throw invalid;
        }
      }
      return EntryShareCopyVaultAuthority._(vkVersion, vdkVersion, generation);
    } catch (_) {
      throw invalid;
    }
  }

  static void _scope(
    Map scope,
    String vaultId,
    EntrySharingSession owner, {
    bool member = false,
  }) {
    if (scope['organizationId'] != owner.organizationId ||
        scope['vaultId'] != vaultId ||
        scope['memberId'] != (member ? owner.principalId : null) ||
        scope['entryId'] != null ||
        scope['grantOrRequestId'] != null ||
        scope['agentId'] != null) {
      throw const EntryShareCopyException(EntryShareCopyError.invalidAuthority);
    }
  }
}
