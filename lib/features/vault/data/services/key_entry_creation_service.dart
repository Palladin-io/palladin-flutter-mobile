import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../autofill/data/autofill_mutation_notifier.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/vault_plaintext.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/entry_v2_contracts.dart';
import 'entry_v2_crypto_service.dart';
import 'vault_crypto_service.dart';

/// Creates one canonical Key revision without exposing plaintext to the server.
final class KeyEntryCreationService {
  KeyEntryCreationService({
    required EntryRemoteDatasource entries,
    required VaultRemoteDatasource vaults,
    required VaultCryptoService vaultCrypto,
    required EntryV2CryptoService entryCrypto,
    required AutoFillMutationNotifier autoFillMutationNotifier,
  }) : _entries = entries,
       _vaults = vaults,
       _vaultCrypto = vaultCrypto,
       _entryCrypto = entryCrypto,
       _autoFillMutationNotifier = autoFillMutationNotifier;

  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final VaultCryptoService _vaultCrypto;
  final EntryV2CryptoService _entryCrypto;
  final AutoFillMutationNotifier _autoFillMutationNotifier;

  Future<EntryEntity> create({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    bool discoverDescription = false,
  }) => _create(
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon,
    content: content,
    memberPrivateKey: memberPrivateKey,
    type: EntryType.key,
    exposeUsername: false,
    exposeDomain: false,
    discoverDescription: discoverDescription,
  );

  Future<EntryEntity> createCredential({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    required bool exposeUsername,
    required bool exposeDomain,
    bool discoverDescription = false,
  }) => _create(
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon,
    content: content,
    memberPrivateKey: memberPrivateKey,
    type: EntryType.credential,
    exposeUsername: exposeUsername,
    exposeDomain: exposeDomain,
    discoverDescription: discoverDescription,
  );

  Future<EntryEntity> createScript({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    bool discoverDescription = false,
  }) => _create(
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon,
    content: content,
    memberPrivateKey: memberPrivateKey,
    type: EntryType.script,
    exposeUsername: false,
    exposeDomain: false,
    discoverDescription: discoverDescription,
  );

  Future<EntryEntity> createCreditCard({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    bool discoverDescription = false,
  }) => _create(
    vaultId: vaultId,
    label: label,
    description: description,
    icon: icon,
    content: content,
    memberPrivateKey: memberPrivateKey,
    type: EntryType.creditCard,
    exposeUsername: false,
    exposeDomain: false,
    discoverDescription: discoverDescription,
  );

  Future<EntryEntity> _create({
    required String vaultId,
    required String label,
    required String description,
    required String icon,
    required Map<String, dynamic> content,
    required Uint8List memberPrivateKey,
    required EntryType type,
    required bool exposeUsername,
    required bool exposeDomain,
    required bool discoverDescription,
  }) async {
    _validateContent(type, content, vaultId);
    final vault = await _vaults.getEncryptedVault(vaultId);
    final entryId = await _entries.issueCreationChallenge(vaultId);
    final privateKeyCopy = Uint8List.fromList(memberPrivateKey);
    OpenedVaultProjection? opened;
    try {
      opened = await _vaultCrypto.openVaultProjection(
        json: vault,
        memberPrivateKey: privateKeyCopy,
      );
      final discoveryKey = opened.vaultDiscoveryKey;
      if (discoveryKey == null) {
        throw const FormatException('Vault discovery key is missing');
      }
      final secret = _memberSecret(
        type,
        label,
        description,
        icon,
        content,
        exposeUsername: exposeUsername,
        exposeDomain: exposeDomain,
        discoverDescription: discoverDescription,
      );
      final envelopes = await _entryCrypto.seal(
        organizationId: opened.organizationId,
        vaultId: opened.vaultId,
        entryId: entryId,
        revision: 1,
        vaultKeyVersion: opened.epoch.vaultKeyVersion,
        vdkVersion: opened.epoch.vdkVersion,
        memberKeyGeneration: opened.memberKeyGeneration,
        operation: 1,
        secret: secret,
        vaultKey: opened.vaultKey,
        vaultDiscoveryKey: discoveryKey,
      );
      final request = CreateEntryV2Request(
        vaultId: vaultId,
        entryId: entryId,
        envelopes: envelopes,
        deliveryPolicy: type.deliveryPolicyWire(),
      ).toJson();
      await _commitCanonicalCreate(vaultId, request);
      final now = DateTime.now().toUtc();
      return EntryEntity(
        id: entryId,
        vaultId: vaultId,
        label: label,
        description: description.isEmpty ? null : description,
        icon: icon.isEmpty ? null : icon,
        type: type,
        createdAt: now,
        updatedAt: now,
      );
    } finally {
      privateKeyCopy.fillRange(0, privateKeyCopy.length, 0);
      opened?.vaultKey.fillRange(0, opened.vaultKey.length, 0);
      opened?.vaultDiscoveryKey?.fillRange(
        0,
        opened.vaultDiscoveryKey!.length,
        0,
      );
    }
  }

  Future<void> _commitCanonicalCreate(
    String vaultId,
    Map<String, dynamic> request,
  ) async {
    // Clear the old provider cache before the server can advance the Entry.
    // If both attempts fail without an HTTP response, the outcome is
    // ambiguous and AutoFill intentionally remains empty until the next
    // authoritative synchronization.
    late final AutoFillMutationLease mutation;
    try {
      mutation = await _autoFillMutationNotifier.beginMutation();
    } catch (_) {
      // The remote transition has not started. Preserve the typed retryable
      // contract used by CreateEntryCubit without exposing platform details.
      throw const EntryException(EntryErrorKind.networkError);
    }
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        await _entries.createCanonicalEntry(vaultId, request);
        await mutation.complete();
        return;
      } on DioException catch (error) {
        if (error.response != null) {
          // A concrete HTTP rejection did not leave an ambiguous mutation.
          await mutation.complete();
          rethrow;
        }
        if (attempt == 1) {
          await mutation.leaveAmbiguous();
          rethrow;
        }
        // Retry the byte-identical immutable transition. The backend
        // recognizes an exact-create retry after a lost 201 response.
      } catch (_) {
        await mutation.leaveAmbiguous();
        rethrow;
      }
    }
  }

  MemberSecret _memberSecret(
    EntryType type,
    String label,
    String description,
    String icon,
    Map<String, dynamic> raw, {
    required bool exposeUsername,
    required bool exposeDomain,
    required bool discoverDescription,
  }) {
    final custom = (raw['fields'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (field) => VaultCustomField(
            id: field['id'] as String,
            label: field['label'] as String? ?? '',
            kind: field['type'] as String,
            value: field['value'],
            includeInMemberIndex: field['agentVisible'] == true,
          ),
        )
        .toList(growable: false);
    final content = switch (type) {
      EntryType.key => KeySecretContent(
        value: raw['value'] as String,
        url: raw['url'] as String?,
        notes: raw['notes'] as String?,
        customFields: custom,
      ),
      EntryType.credential => CredentialSecretContent(
        username: raw['username'] as String,
        password: raw['password'] as String,
        url: raw['url'] as String?,
        urlDomain: _domain(raw['url'] as String? ?? ''),
        totp: null,
        notes: raw['notes'] as String?,
        customFields: custom,
      ),
      EntryType.script => ScriptSecretContent(
        source: raw['script'] as String,
        interpreter: raw['interpreter'] as String,
        refs: (raw['refs'] as List)
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList(),
        notes: raw['notes'] as String?,
        customFields: custom,
      ),
      EntryType.creditCard => CreditCardSecretContent(
        cardholderName: raw['cardholderName'] as String,
        cardNumber: raw['cardNumber'] as String,
        expiryMonth: raw['expiryMonth'] as String,
        expiryYear: raw['expiryYear'] as String,
        billingAddress: raw['billingAddress'] as String?,
        notes: raw['notes'] as String?,
        customFields: custom,
      ),
    };
    final fields = <String, AgentFieldAccess>{
      'memberLabel': AgentFieldAccess.never,
      'agentLabel': AgentFieldAccess.discovery,
      'description': discoverDescription
          ? AgentFieldAccess.discovery
          : AgentFieldAccess.never,
      'icon': AgentFieldAccess.never,
      'color': AgentFieldAccess.never,
      'entryType': AgentFieldAccess.discovery,
      ...switch (type) {
        EntryType.key => {
          'key.value': AgentFieldAccess.onGrantValue,
          if (raw['url'] != null) 'key.url': AgentFieldAccess.onGrantValue,
          'notes': AgentFieldAccess.onGrantValue,
        },
        EntryType.credential => {
          'credential.username': exposeUsername
              ? AgentFieldAccess.discovery
              : AgentFieldAccess.onGrantValue,
          'credential.password': AgentFieldAccess.onGrantValue,
          'credential.url': AgentFieldAccess.onGrantValue,
          'credential.urlDomain': exposeDomain
              ? AgentFieldAccess.discovery
              : AgentFieldAccess.never,
          'credential.totp': AgentFieldAccess.onGrantDerived,
          'notes': AgentFieldAccess.onGrantValue,
        },
        EntryType.script => {
          'script.source': AgentFieldAccess.onGrantRuntime,
          'script.interpreter': AgentFieldAccess.discovery,
          'script.refs': AgentFieldAccess.onGrantRuntime,
          'notes': AgentFieldAccess.onGrantValue,
        },
        EntryType.creditCard => {
          'creditCard.cardholderName': AgentFieldAccess.onGrantRuntime,
          'creditCard.cardNumber': AgentFieldAccess.onGrantRuntime,
          'creditCard.expiryMonth': AgentFieldAccess.onGrantRuntime,
          'creditCard.expiryYear': AgentFieldAccess.onGrantRuntime,
          'creditCard.billingAddress': raw['billingAddress'] == null
              ? AgentFieldAccess.never
              : AgentFieldAccess.onGrantRuntime,
          'notes': AgentFieldAccess.never,
        },
      },
      for (final field in custom)
        field.fieldId: field.kind == 'totp'
            ? AgentFieldAccess.onGrantDerived
            : type == EntryType.creditCard
            ? AgentFieldAccess.onGrantRuntime
            : field.includeInMemberIndex
            ? AgentFieldAccess.discovery
            : type == EntryType.script
            ? AgentFieldAccess.onGrantRuntime
            : AgentFieldAccess.onGrantValue,
    };
    return MemberSecret(
      entryType: VaultEntryType.values[type.index],
      memberLabel: label,
      agentLabel: label,
      description: description.isEmpty ? null : description,
      icon: VaultPlaintextIcon.fromReference(icon),
      color: null,
      discoverable: true,
      content: content,
      agentFieldAccess: fields,
    );
  }

  void _validateContent(
    EntryType type,
    Map<String, dynamic> content,
    String vaultId,
  ) {
    final acceptedType = switch (type) {
      EntryType.key => const {0, 'KEY'},
      EntryType.credential => const {1, 'CREDENTIAL'},
      EntryType.script => const {2, 'SCRIPT'},
      EntryType.creditCard => const {3, 'CREDIT_CARD'},
    };
    if (!acceptedType.contains(content['type'])) {
      throw const FormatException('Entry content type mismatch');
    }
    if (type == EntryType.credential &&
        (content['username'] is! String || content['password'] is! String)) {
      throw const FormatException('Malformed Credential content');
    }
    if (type == EntryType.creditCard &&
        (content['cardholderName'] is! String ||
            content['cardNumber'] is! String ||
            content['expiryMonth'] is! String ||
            content['expiryYear'] is! String)) {
      throw const FormatException('Malformed Credit Card content');
    }
    if (type == EntryType.creditCard) {
      CreditCardPayload.rejectRetiredDedicatedFields(content);
    }
    if (type == EntryType.script) {
      if (content['script'] is! String ||
          (content['script'] as String).trim().isEmpty ||
          content['interpreter'] is! String ||
          content['refs'] is! List) {
        throw const FormatException('Malformed Script content');
      }
      final environments = <String>{};
      for (final value in content['refs'] as List) {
        if (value is! Map ||
            value['env'] is! String ||
            value['entryId'] is! String ||
            value['field'] is! String ||
            (value['vaultId'] != null && value['vaultId'] != vaultId)) {
          throw const FormatException('Invalid Script reference scope');
        }
        final env = value['env'] as String;
        if (!RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(env) ||
            !environments.add(env)) {
          throw const FormatException('Invalid Script reference');
        }
      }
    }
    final fields = content['fields'];
    if (fields is List) {
      for (final field in fields) {
        if (field is! Map) throw const FormatException('Malformed field');
        if (field['type'] == 'totp' && field['value'] is! String) {
          throw const FormatException('Malformed TOTP');
        }
      }
    } else if (fields != null) {
      throw const FormatException('Malformed fields');
    }
  }

  String? _domain(String raw) {
    final normalized = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.toLowerCase();
    return host == null || host.isEmpty ? null : host;
  }
}
