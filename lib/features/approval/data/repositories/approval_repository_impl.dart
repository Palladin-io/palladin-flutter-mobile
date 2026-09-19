import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/datasources/entry_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
import '../../../vault/data/services/canonical_entry_detail_service.dart';
import '../../../vault/data/services/agent_visibility_projector.dart';
import '../../../vault/data/services/entry_v2_crypto_service.dart';
import '../../../vault/data/services/vault_rotation_crypto_service.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import '../services/script_execution_package_service.dart';
import '../services/pending_grant_reason_binding.dart';
import '../../../vault/data/datasources/agent_discovery_remote_datasource.dart';
import '../../../vault/domain/entities/agent_visibility_policy.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../domain/entities/pending_grant.dart';
import '../../domain/exceptions/approval_exceptions.dart';
import '../../domain/repositories/approval_repository.dart';
import '../datasources/approval_remote_datasource.dart';

/// Concrete [ApprovalRepository].
///
/// Orchestrates the GRANULAR approval pipeline:
///   1. fetch the entry's encrypted blob (`GET .../entries/{id}`),
///   2. fetch the vault's sealed VK (`GET /api/vaults/{id}`),
///   3. produce the envelope on-device ([GrantCryptoService]),
///   4. submit it (`PUT .../approve`).
///
/// Reuses the vault feature's entry + vault datasources rather than
/// duplicating those routes. Translates wire / crypto failures into typed
/// [ApprovalException]s. No secret material is logged.
class ApprovalRepositoryImpl implements ApprovalRepository {
  ApprovalRepositoryImpl({
    required ApprovalRemoteDatasource approvalDatasource,
    required EntryRemoteDatasource entryDatasource,
    required VaultRemoteDatasource vaultDatasource,
    required EntryV2CryptoService cryptoService,
    required VaultRotationCryptoService vaultKeys,
    required CanonicalEntryDetailService canonicalEntries,
    required AgentDiscoveryRemote discovery,
    ScriptExecutionPackageService? scriptPackages,
  }) : _approval = approvalDatasource,
       _entries = entryDatasource,
       _vaults = vaultDatasource,
       _crypto = cryptoService,
       _vaultKeys = vaultKeys,
       _canonicalEntries = canonicalEntries,
       _discovery = discovery,
       _scriptPackages = scriptPackages ?? ScriptExecutionPackageService();

  final ApprovalRemoteDatasource _approval;
  final EntryRemoteDatasource _entries;
  final VaultRemoteDatasource _vaults;
  final EntryV2CryptoService _crypto;
  final VaultRotationCryptoService _vaultKeys;
  final CanonicalEntryDetailService _canonicalEntries;
  final AgentDiscoveryRemote _discovery;
  final ScriptExecutionPackageService _scriptPackages;

  @override
  Future<List<PendingGrant>> listPendingGrants() async {
    try {
      AppLogger.d('Approval', 'GET /api/dashboard/pending-grants');
      final result = <PendingGrant>[];
      final seen = <String>{};
      String? cursor;
      do {
        final page = await _approval.listPendingGrants(cursor: cursor);
        result.addAll(page.items.map((model) => model.toEntity()));
        if (result.length > 2000) {
          throw const FormatException('Pending grant list exceeds limit');
        }
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw const FormatException('Pending grant cursor did not advance');
        }
      } while (cursor != null);
      return List.unmodifiable(result);
    } on DioException catch (e) {
      AppLogger.w('Approval', 'pending grant list request failed');
      throw ApprovalException(_classifyError(e));
    }
  }

  @override
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
    required List<String> fieldIds,
    required String reviewedEntryRevision,
  }) async {
    var stage = 'grant-fetch';
    CanonicalEntrySnapshot? snapshot;
    try {
      final freshGrant = (await _approval.getGrant(
        grant.vaultId,
        grant.grantId,
      )).toEntity();
      stage = 'request-validation';
      final reason = requireBoundGrantReason(grant);
      final freshReason = requireBoundGrantReason(freshGrant);
      if (freshReason.requestRevision != reason.requestRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      stage = 'entry-reveal';
      snapshot = await _canonicalEntries.reveal(
        expected: EntryEntity(
          id: grant.entryId,
          vaultId: grant.vaultId,
          label: '',
          type: EntryType.key,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        memberPrivateKey: privateKey,
      );
      if (snapshot.entry['currentRevision'] != reviewedEntryRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      stage = 'vault-fetch';
      final vault = await _vaults.getEncryptedVault(grant.vaultId);
      stage = 'agent-discovery';
      final candidates = (await _discovery.list(grant.vaultId))
          .where((item) => item.agentId == grant.agentId && item.isCurrent)
          .toList(growable: false);
      if (candidates.length != 1) {
        throw const FormatException('Agent identity unavailable');
      }
      stage = 'scope-projection';
      final candidate = candidates.single;
      final type = EntryTypeExtension.fromWire(
        snapshot.secret['entryType'] as int,
      );
      final policy = AgentVisibilityPolicy.fromJson(
        type,
        Map<String, dynamic>.from(
          snapshot.secret['agentVisibilityPolicy'] as Map,
        ),
        content: snapshot.payload,
      );
      final agentLabel =
          snapshot.secret['agentLabel'] as String? ??
          snapshot.secret['memberLabel'] as String;
      final description = snapshot.secret['description'] as String? ?? '';
      final grantableFieldIds = AgentVisibilityProjector.grantableFieldIds(
        type: type,
        agentLabel: agentLabel,
        description: description,
        content: snapshot.payload,
        policy: policy,
      ).toSet();
      final reviewedFieldIds = fieldIds.toSet();
      if (reviewedFieldIds.isEmpty ||
          reviewedFieldIds.length != fieldIds.length ||
          reviewedFieldIds.length != grantableFieldIds.length ||
          !reviewedFieldIds.containsAll(grantableFieldIds)) {
        throw const FormatException('Approved fields differ from review');
      }
      final approvedFieldIds = reviewedFieldIds.toList(growable: false)..sort();
      if (approvedFieldIds.isEmpty) {
        throw const FormatException('Entry has no grantable fields');
      }
      final approvedMethods = _methodBits(methods);
      final requestedMethods = reason.requestedMethods;
      if (approvedMethods == 0 ||
          (approvedMethods & requestedMethods) != approvedMethods) {
        throw const FormatException('Approval methods exceed request');
      }
      final wire = limit.toWire();
      final grantPayload = AgentVisibilityProjector.grantPayload(
        type: type,
        vaultId: grant.vaultId,
        agentLabel: agentLabel,
        description: description,
        content: snapshot.payload,
        policy: policy,
        approvedFieldIds: approvedFieldIds,
      );
      final envelopeFieldIds = AgentVisibilityProjector.grantPayloadFieldIds(
        grantPayload,
      );
      final recipientKey = VaultProtocolBytes.base64Decode(
        candidate.x25519PublicKey,
        maximumBytes: 32,
      );
      if (recipientKey.length != 32) {
        throw const FormatException('Invalid Agent recipient key');
      }
      stage = 'grant-seal';
      final grantEntry = await _crypto.sealGrant(
        organizationId: snapshot.entry['organizationId'] as String,
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        agentId: grant.agentId,
        entryId: grant.entryId,
        entryRevision: int.parse(reviewedEntryRevision),
        memberKeyGeneration: vault['memberKeyGeneration'] as int,
        recipientKeyVersion: candidate.recipientKeyVersion,
        agentPublicKey: Uint8List.fromList(recipientKey),
        approvedMethods: approvedMethods,
        deliveryPolicy: type.deliveryPolicyCode(),
        fieldIds: envelopeFieldIds,
        grantPayload: grantPayload,
        expiresAt: wire.expiresAt == null
            ? null
            : DateTime.parse(wire.expiresAt!),
        remainingUses: wire.queryLimit,
      );
      stage = 'entry-revision-check';
      final latest = await _entries.getCanonicalEntry(
        grant.vaultId,
        grant.entryId,
      );
      if (latest['currentRevision'] != reviewedEntryRevision) {
        throw const ApprovalException(ApprovalErrorKind.conflict);
      }
      stage = 'grant-submit';
      await _approval.approveGrant(
        vaultId: grant.vaultId,
        grantId: grant.grantId,
        grantEntry: grantEntry,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (e) {
      AppLogger.w(
        'Approval',
        'Approve failed at $stage (DioException:${e.response?.statusCode ?? 'none'})',
      );
      throw ApprovalException(_classifyError(e));
    } on ApprovalException {
      rethrow;
    } catch (error) {
      // Stage and exception class are safe operational metadata. Exception
      // messages may contain parser input and are deliberately not logged.
      AppLogger.w(
        'Approval',
        'Approve failed at $stage (${error.runtimeType})',
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    } finally {
      snapshot?.clear();
    }
  }

  int _methodBits(Iterable<GrantMethod> methods) => methods.fold(
    0,
    (bits, method) =>
        bits |
        switch (method) {
          GrantMethod.get => 1,
          GrantMethod.exec => 2,
          GrantMethod.inject => 4,
        },
  );

  @override
  Future<void> createFullGrant({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    if (recipientKeyVersion <= 0 || agentAccessEpoch <= 0) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    final grantId = _uuidV4();
    final wire = limit.toWire();
    final methodBits = _methodBits(methods);
    if (methodBits == 0) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    Uint8List? vaultKey;
    Uint8List? vaultSigningPrivateKey;
    try {
      final vault = await _vaults.getEncryptedVault(vaultId);
      final organizationId = vault['organizationId'];
      final memberKeyGeneration = vault['memberKeyGeneration'];
      final epochValue = vault['currentKeyEpoch'];
      if (organizationId is! String ||
          memberKeyGeneration is! int ||
          epochValue is! Map) {
        throw const FormatException('Malformed encrypted Vault key context');
      }
      final epoch = Map<String, dynamic>.from(epochValue);
      final vaultKeyVersion = epoch['vaultKeyVersion'];
      final vaultSigningKeyVersion = epoch['manifestSigningKeyVersion'];
      if (vaultKeyVersion is! int || vaultSigningKeyVersion is! int) {
        throw const FormatException('Malformed encrypted Vault key epoch');
      }
      final memberEnvelope = Map<String, dynamic>.from(
        vault['memberVaultKey'] as Map,
      );
      vaultKey = await _vaultKeys.openMemberVaultKey(
        memberEnvelope,
        privateKey,
        expectedOrganizationId: organizationId,
        expectedVaultId: vaultId,
        expectedVaultKeyVersion: vaultKeyVersion,
        expectedMemberKeyGeneration: memberKeyGeneration,
      );
      final signingEnvelope = (vault['vaultPrivateKeys'] as List)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .singleWhere(
            (value) =>
                EnvelopePurpose.parseWire(
                  (value['descriptor'] as Map)['purpose'],
                ) ==
                EnvelopePurpose.manifestPrivateByVk,
          );
      vaultSigningPrivateKey = await _vaultKeys
          .openCanonicalManifestSigningPrivateKey(
            signingEnvelope,
            vaultKey,
            expectedKeyVersion: vaultSigningKeyVersion,
          );
      final agentWrappedVaultKey = await _crypto.sealAgentVaultKey(
        vaultKey: vaultKey,
        organizationId: organizationId,
        vaultId: vaultId,
        grantId: grantId,
        agentId: agentId,
        agentAccessEpoch: agentAccessEpoch,
        vaultKeyVersion: vaultKeyVersion,
        agentPublicKey: Uint8List.fromList(base64.decode(agentPublicKey)),
        recipientKeyVersion: recipientKeyVersion,
        vaultSigningKeyVersion: vaultSigningKeyVersion,
        vaultSigningPrivateKey: vaultSigningPrivateKey,
      );
      await _approval.createFullGrant(
        vaultId: vaultId,
        grantId: grantId,
        agentId: agentId,
        agentWrappedVaultKey: agentWrappedVaultKey,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(methods),
      );
    } on DioException catch (e) {
      throw ApprovalException(_classifyError(e));
    } on ApprovalException {
      rethrow;
    } catch (e, s) {
      AppLogger.e('Approval', 'FULL re-grant failed', error: e, stackTrace: s);
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
      vaultSigningPrivateKey?.fillRange(0, vaultSigningPrivateKey.length, 0);
    }
  }

  @override
  Future<void> createGranularGrant({
    required String vaultId,
    required String entryId,
    List<String>? selectedFieldIds,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  }) async {
    if (recipientKeyVersion <= 0 || agentAccessEpoch <= 0) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    final grantId = _uuidV4();
    final wire = limit.toWire();
    final methodBits = _methodBits(methods);
    if (methodBits == 0) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    // GRANULAR retains one revision/field/method-bound envelope.
    try {
      final snapshot = await _canonicalEntries.reveal(
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: '',
          type: EntryType.key,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        memberPrivateKey: privateKey,
      );
      try {
        final type = EntryTypeExtension.fromWire(
          snapshot.secret['entryType'] as int,
        );
        if (type == EntryType.script) {
          throw const ApprovalException(ApprovalErrorKind.validation);
        }
        final policy = AgentVisibilityPolicy.fromJson(
          type,
          Map<String, dynamic>.from(
            snapshot.secret['agentVisibilityPolicy'] as Map,
          ),
          content: snapshot.payload,
        );
        final approved = AgentVisibilityProjector.grantableFieldIds(
          type: type,
          agentLabel:
              snapshot.secret['agentLabel'] as String? ??
              snapshot.secret['memberLabel'] as String,
          description: snapshot.secret['description'] as String? ?? '',
          content: snapshot.payload,
          policy: policy,
        );
        final payload = AgentVisibilityProjector.grantPayload(
          type: type,
          vaultId: vaultId,
          agentLabel:
              snapshot.secret['agentLabel'] as String? ??
              snapshot.secret['memberLabel'] as String,
          description: snapshot.secret['description'] as String? ?? '',
          content: snapshot.payload,
          policy: policy,
          approvedFieldIds: selectedFieldIds == null
              ? approved
              : AgentVisibilityProjector.retainGrantableFields(
                  type: type,
                  selectedFieldIds: selectedFieldIds,
                  grantableFieldIds: approved,
                ),
        );
        final envelopeFieldIds = AgentVisibilityProjector.grantPayloadFieldIds(
          payload,
        );
        final envelope = await _crypto.sealGrant(
          organizationId: snapshot.entry['organizationId'] as String,
          vaultId: vaultId,
          entryId: entryId,
          grantId: grantId,
          agentId: agentId,
          entryRevision: int.parse(snapshot.entry['currentRevision'] as String),
          memberKeyGeneration: snapshot.entry['memberKeyGeneration'] as int,
          agentPublicKey: Uint8List.fromList(base64.decode(agentPublicKey)),
          recipientKeyVersion: recipientKeyVersion,
          approvedMethods: methodBits,
          deliveryPolicy: type.deliveryPolicyCode(),
          fieldIds: envelopeFieldIds,
          grantPayload: payload,
          expiresAt: wire.expiresAt == null
              ? null
              : DateTime.parse(wire.expiresAt!),
          remainingUses: wire.queryLimit,
        );
        await _approval.createGranularGrant(
          vaultId: vaultId,
          entryId: entryId,
          grantId: grantId,
          agentId: agentId,
          grantEntry: Map<String, dynamic>.from(envelope),
          selectedFieldIds: selectedFieldIds,
          expiresAt: wire.expiresAt,
          queryLimit: wire.queryLimit,
          methods: serializeGrantMethods(methods),
        );
      } finally {
        snapshot.clear();
      }
    } on ApprovalException {
      rethrow;
    } on DioException catch (e, s) {
      AppLogger.e(
        'Approval',
        'GRANULAR re-grant failed',
        error: e,
        stackTrace: s,
      );
      throw ApprovalException(_classifyError(e));
    } catch (e, s) {
      AppLogger.e(
        'Approval',
        're-grant envelope failed',
        error: e,
        stackTrace: s,
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    }
  }

  @override
  Future<void> createScriptExecutionGrant({
    required String vaultId,
    required String scriptEntryId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
  }) async {
    if (recipientKeyVersion <= 0 || agentAccessEpoch <= 0) {
      throw const ApprovalException(ApprovalErrorKind.validation);
    }

    final grantId = _uuidV4();
    final wire = limit.toWire();
    CanonicalEntrySnapshot? script;
    Uint8List? vaultKey;
    Uint8List? vaultSigningPrivateKey;
    Uint8List? agentRecipientKey;
    final references = <CanonicalGrantFieldProjection>[];
    final encodedReferences = <ScriptExecutionPackageEntryInput>[];
    try {
      final vault = await _vaults.getEncryptedVault(vaultId);
      final organizationId = vault['organizationId'];
      final memberKeyGeneration = vault['memberKeyGeneration'];
      final epochValue = vault['currentKeyEpoch'];
      if (organizationId is! String ||
          memberKeyGeneration is! int ||
          epochValue is! Map) {
        throw const FormatException('Malformed encrypted Vault key context');
      }
      final epoch = Map<String, dynamic>.from(epochValue);
      final vaultKeyVersion = epoch['vaultKeyVersion'];
      final vaultSigningKeyVersion = epoch['manifestSigningKeyVersion'];
      if (vaultKeyVersion is! int || vaultSigningKeyVersion is! int) {
        throw const FormatException('Malformed encrypted Vault key epoch');
      }
      vaultKey = await _vaultKeys.openMemberVaultKey(
        Map<String, dynamic>.from(vault['memberVaultKey'] as Map),
        privateKey,
        expectedOrganizationId: organizationId,
        expectedVaultId: vaultId,
        expectedVaultKeyVersion: vaultKeyVersion,
        expectedMemberKeyGeneration: memberKeyGeneration,
      );
      final signingEnvelope = (vault['vaultPrivateKeys'] as List)
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .singleWhere(
            (value) =>
                EnvelopePurpose.parseWire(
                  (value['descriptor'] as Map)['purpose'],
                ) ==
                EnvelopePurpose.manifestPrivateByVk,
          );
      vaultSigningPrivateKey = await _vaultKeys
          .openCanonicalManifestSigningPrivateKey(
            signingEnvelope,
            vaultKey,
            expectedKeyVersion: vaultSigningKeyVersion,
          );
      script = await _canonicalEntries.reveal(
        expected: EntryEntity(
          id: scriptEntryId,
          vaultId: vaultId,
          label: '',
          type: EntryType.script,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        memberPrivateKey: privateKey,
      );
      if (script.secret['entryType'] != EntryType.script.toWire()) {
        throw const FormatException('Script grant targets a non-Script');
      }

      final fieldIdsByEntry = <String, Set<String>>{};
      for (final ref in ScriptRef.listFromPayload(script.payload)) {
        fieldIdsByEntry
            .putIfAbsent(ref.entryId, () => <String>{})
            .add(ref.field);
      }
      final referencedEntryIds = fieldIdsByEntry.keys.toList()..sort();
      for (final entryId in referencedEntryIds) {
        references.add(
          await _canonicalEntries.projectGrantFields(
            expected: EntryEntity(
              id: entryId,
              vaultId: vaultId,
              label: '',
              type: EntryType.key,
              createdAt: DateTime.fromMillisecondsSinceEpoch(0),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
            memberPrivateKey: privateKey,
            fieldIds: fieldIdsByEntry[entryId]!,
          ),
        );
      }
      for (final projection in references) {
        encodedReferences.add(
          ScriptExecutionPackageEntryInput(
            entryId: projection.entryId,
            entryRevision: projection.entryRevision,
            fieldIds: projection.fieldIds,
            encodedGrantPayload: projection.encodedGrantPayload,
          ),
        );
      }

      agentRecipientKey = VaultProtocolBytes.base64Decode(
        agentPublicKey,
        maximumBytes: 32,
      );
      if (agentRecipientKey.length != 32) {
        throw const FormatException('Invalid Agent recipient key');
      }
      final package = await _scriptPackages.seal(
        grantId: grantId,
        packageRevision: 1,
        agentId: agentId,
        agentAccessEpoch: agentAccessEpoch,
        agentPublicKey: agentRecipientKey,
        recipientAgentKeyVersion: recipientKeyVersion,
        vaultSigningKeyVersion: vaultSigningKeyVersion,
        vaultSigningPrivateKey: vaultSigningPrivateKey,
        scriptEntry: script.entry,
        scriptPayload: script.payload,
        referencedEntries: encodedReferences,
      );
      await _approval.createScriptExecutionGrant(
        vaultId: vaultId,
        scriptEntryId: scriptEntryId,
        grantId: grantId,
        agentId: agentId,
        scriptPackage: package,
        expiresAt: wire.expiresAt,
        queryLimit: wire.queryLimit,
        methods: serializeGrantMethods(const [GrantMethod.exec]),
      );
    } on DioException catch (error) {
      throw ApprovalException(_classifyError(error));
    } on ApprovalException {
      rethrow;
    } catch (error) {
      AppLogger.w(
        'Approval',
        'Script execution grant failed (${error.runtimeType})',
      );
      throw const ApprovalException(ApprovalErrorKind.cryptoFailure);
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
      vaultSigningPrivateKey?.fillRange(0, vaultSigningPrivateKey.length, 0);
      agentRecipientKey?.fillRange(0, agentRecipientKey.length, 0);
      script?.clear();
      for (final projection in references) {
        projection.clear();
      }
    }
  }

  String _uuidV4() {
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    bytes.fillRange(0, bytes.length, 0);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  Future<void> denyGrant({required PendingGrant grant}) async {
    try {
      AppLogger.d('Approval', 'PUT deny grantId=${grant.grantId}');
      await _approval.denyGrant(vaultId: grant.vaultId, grantId: grant.grantId);
    } on DioException catch (e, s) {
      AppLogger.e('Approval', 'deny failed', error: e, stackTrace: s);
      throw ApprovalException(_classifyError(e));
    }
  }

  ApprovalErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return ApprovalErrorKind.networkError;
    }
    return switch (e.response?.statusCode) {
      404 => ApprovalErrorKind.notFound,
      403 => ApprovalErrorKind.forbidden,
      400 => ApprovalErrorKind.validation,
      409 => ApprovalErrorKind.conflict,
      _ => ApprovalErrorKind.unknown,
    };
  }
}
