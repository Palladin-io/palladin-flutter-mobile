import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/import_draft.dart';
import '../../domain/entities/totp_config.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/entry_v2_contracts.dart';
import 'entry_v2_crypto_service.dart';
import 'vault_crypto_service.dart';

enum CanonicalImportPreparationStage {
  vaultShape,
  vaultOpen,
  routeBinding,
  wrapperVaultBinding,
  organizationBinding,
  memberGenerationBinding,
  keyEpochBinding,
  discoveryKey,
  entryPlaintext,
  entrySeal,
}

final class CanonicalImportPreparationException implements Exception {
  const CanonicalImportPreparationException(this.stage, [this.causeType]);

  final CanonicalImportPreparationStage stage;
  final String? causeType;
}

/// Builds complete protocol-2 import transitions entirely on-device.
///
/// Import deliberately uses the same canonical [EntryV2CryptoService] as the
/// regular Create Entry flow. Keeping one envelope pipeline prevents the bulk
/// endpoint from drifting to a different descriptor or ciphertext shape.
class CanonicalImportProjectionService {
  CanonicalImportProjectionService({
    required VaultRemoteDatasource vaults,
    required VaultCryptoService vaultCrypto,
    required EntryV2CryptoService entryCrypto,
  }) : _vaults = vaults,
       _vaultCrypto = vaultCrypto,
       _entryCrypto = entryCrypto;

  final VaultRemoteDatasource _vaults;
  final VaultCryptoService _vaultCrypto;
  final EntryV2CryptoService _entryCrypto;

  Future<List<Map<String, dynamic>>> prepareCredentialBatch({
    required String vaultId,
    required List<String> entryIds,
    required List<ImportEntryDraft> drafts,
    required Uint8List memberPrivateKey,
  }) async {
    if (entryIds.length != drafts.length ||
        drafts.isEmpty ||
        drafts.length > 50) {
      throw const FormatException('Invalid import batch');
    }
    final vault = await _vaults.getEncryptedVault(vaultId);
    final organizationValue = vault['organizationId'];
    final generationValue = vault['memberKeyGeneration'];
    final epochValue = vault['currentKeyEpoch'];
    if (organizationValue is! String ||
        generationValue is! int ||
        epochValue is! Map ||
        epochValue['vaultKeyVersion'] is! int ||
        epochValue['vdkVersion'] is! int) {
      throw const CanonicalImportPreparationException(
        CanonicalImportPreparationStage.vaultShape,
      );
    }
    final organizationId = organizationValue;
    final generation = generationValue;
    final epoch = Map<String, dynamic>.from(epochValue);
    final vkVersion = epoch['vaultKeyVersion']! as int;
    final vdkVersion = epoch['vdkVersion']! as int;
    OpenedVaultProjection? openedVault;
    try {
      try {
        openedVault = await _vaultCrypto.openVaultProjection(
          json: vault,
          memberPrivateKey: memberPrivateKey,
        );
      } catch (error) {
        throw CanonicalImportPreparationException(
          CanonicalImportPreparationStage.vaultOpen,
          error.runtimeType.toString(),
        );
      }

      // The route and authenticated top-level Vault projection are the
      // independent authority for bindings carried inside encrypted wrappers.
      if (vault['id'] != vaultId) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.routeBinding,
        );
      }
      if (openedVault.vaultId != vaultId) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.wrapperVaultBinding,
        );
      }
      if (openedVault.organizationId != organizationId) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.organizationBinding,
        );
      }
      if (openedVault.memberKeyGeneration != generation) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.memberGenerationBinding,
        );
      }
      if (openedVault.epoch.vaultKeyVersion != vkVersion ||
          openedVault.epoch.vdkVersion != vdkVersion) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.keyEpochBinding,
        );
      }
      final discoveryKey = openedVault.vaultDiscoveryKey;
      if (discoveryKey == null) {
        throw const CanonicalImportPreparationException(
          CanonicalImportPreparationStage.discoveryKey,
        );
      }

      final output = <Map<String, dynamic>>[];
      for (var index = 0; index < drafts.length; index++) {
        final draft = drafts[index];
        if (draft.type != EntryType.credential) {
          throw const FormatException('Import type is not supported');
        }

        late final MemberSecret secret;
        try {
          secret = _credentialSecret(draft);
        } catch (error) {
          throw CanonicalImportPreparationException(
            CanonicalImportPreparationStage.entryPlaintext,
            error.runtimeType.toString(),
          );
        }

        late final EntryEnvelopeBundleModel envelopes;
        try {
          envelopes = await _entryCrypto.seal(
            organizationId: organizationId,
            vaultId: vaultId,
            entryId: entryIds[index],
            revision: 1,
            vaultKeyVersion: vkVersion,
            vdkVersion: vdkVersion,
            memberKeyGeneration: generation,
            operation: 1,
            secret: secret,
            vaultKey: openedVault.vaultKey,
            vaultDiscoveryKey: discoveryKey,
          );
        } catch (error) {
          throw CanonicalImportPreparationException(
            CanonicalImportPreparationStage.entrySeal,
            error.runtimeType.toString(),
          );
        }

        output.add({
          'entryId': entryIds[index],
          'entryKey': envelopes.entryKey,
          'memberIndex': envelopes.memberIndex,
          'memberSecret': envelopes.memberSecret,
          'agentDiscovery': envelopes.agentDiscovery,
          'deliveryPolicy': draft.type.deliveryPolicyWire(),
        });
      }
      return output;
    } finally {
      openedVault?.vaultKey.fillRange(0, openedVault.vaultKey.length, 0);
      openedVault?.vaultDiscoveryKey?.fillRange(
        0,
        openedVault.vaultDiscoveryKey!.length,
        0,
      );
    }
  }

  MemberSecret _credentialSecret(ImportEntryDraft draft) {
    final payload = draft.payload;
    final username = payload['username'];
    final password = payload['password'];
    if (username is! String || password is! String) {
      throw const FormatException('Malformed Credential content');
    }
    final url = payload['url'];
    final notes = payload['notes'];
    final rawTotp = payload['totp'];
    if ((url != null && url is! String) ||
        (notes != null && notes is! String) ||
        (rawTotp != null && rawTotp is! String)) {
      throw const FormatException('Malformed Credential content');
    }

    final fields = _customFields(payload['fields']);
    return MemberSecret(
      entryType: VaultEntryType.credential,
      memberLabel: _nfc(draft.label),
      agentLabel: _nfc(draft.label),
      description: draft.description == null ? null : _nfc(draft.description!),
      icon: VaultPlaintextIcon.fromReference(draft.icon),
      color: null,
      discoverable: true,
      content: CredentialSecretContent(
        username: _nfc(username),
        password: _nfc(password),
        url: url == null ? null : _nfc(url),
        urlDomain: _domain(url),
        totp: rawTotp == null ? null : _canonicalTotp(rawTotp),
        notes: notes == null ? null : _nfc(notes),
        customFields: fields,
      ),
      agentFieldAccess: {
        'memberLabel': AgentFieldAccess.never,
        'agentLabel': AgentFieldAccess.discovery,
        'description': AgentFieldAccess.never,
        'icon': AgentFieldAccess.never,
        'color': AgentFieldAccess.never,
        'entryType': AgentFieldAccess.discovery,
        'credential.username': AgentFieldAccess.discovery,
        'credential.password': AgentFieldAccess.onGrantValue,
        'credential.url': AgentFieldAccess.onGrantValue,
        'credential.urlDomain': AgentFieldAccess.discovery,
        'credential.totp': AgentFieldAccess.onGrantDerived,
        'notes': AgentFieldAccess.onGrantValue,
        for (final field in fields)
          field.fieldId: field.kind == 'totp'
              ? AgentFieldAccess.onGrantDerived
              : AgentFieldAccess.onGrantValue,
      },
    );
  }

  List<VaultCustomField> _customFields(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw const FormatException('Malformed fields');
    return value
        .map((raw) {
          if (raw is! Map ||
              raw['id'] is! String ||
              raw['type'] is! String ||
              (raw['label'] != null && raw['label'] is! String)) {
            throw const FormatException('Malformed field');
          }
          final kind = raw['type']! as String;
          return VaultCustomField(
            id: raw['id']! as String,
            label: _nfc((raw['label'] as String?) ?? ''),
            kind: _nfc(kind),
            value: raw['value'],
            includeInMemberIndex: raw['agentVisible'] == true,
          );
        })
        .toList(growable: false);
  }

  Map<String, Object?> _canonicalTotp(String raw) {
    final parsed = TotpConfig.parseUri(raw);
    if (parsed == null || (parsed.digits != 6 && parsed.digits != 8)) {
      throw const FormatException('Invalid TOTP');
    }
    return {
      'secret': parsed.secret,
      'algorithm': parsed.algorithm.wireName,
      'digits': parsed.digits,
      'period': parsed.period,
      'issuer': parsed.issuer == null ? null : _nfc(parsed.issuer!),
      'account': parsed.account == null ? null : _nfc(parsed.account!),
    };
  }

  String? _domain(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  String _nfc(String value) => unicode.nfc(value);
}
