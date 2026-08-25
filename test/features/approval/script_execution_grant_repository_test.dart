import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';
import 'package:mobile_palladin/features/approval/data/repositories/approval_repository_impl.dart';
import 'package:mobile_palladin/features/approval/data/services/script_execution_package_service.dart';
import 'package:mobile_palladin/features/approval/domain/exceptions/approval_exceptions.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant_method.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';

class _Approval extends Mock implements ApprovalRemoteDatasource {}

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Crypto extends Mock implements EntryV2CryptoService {}

class _VaultKeys extends Mock implements VaultRotationCryptoService {}

class _Canonical extends Mock implements CanonicalEntryDetailService {}

class _Discovery extends Mock implements AgentDiscoveryRemote {}

class _Packages extends Mock implements ScriptExecutionPackageService {}

class _Entry extends Fake implements EntryEntity {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_Entry());
    registerFallbackValue(<String>{});
    registerFallbackValue(<ScriptExecutionPackageEntryInput>[]);
    registerFallbackValue(
      CanonicalEntrySnapshot(entry: {}, payload: {}, secret: {}),
    );
  });

  test('four Script references create one ScriptExecution grant POST', () async {
    const organizationId = '11111111-1111-4111-8111-111111111111';
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const scriptId = '33333333-3333-4333-8333-333333333333';
    const agentId = '55555555-5555-4555-8555-555555555555';
    const refIds = [
      '66666666-6666-4666-8666-666666666661',
      '66666666-6666-4666-8666-666666666662',
      '66666666-6666-4666-8666-666666666663',
      '66666666-6666-4666-8666-666666666664',
    ];
    final approval = _Approval();
    final canonical = _Canonical();
    final packages = _Packages();
    final vaults = _Vaults();
    final vaultKeys = _VaultKeys();
    final package = <String, dynamic>{
      'contractVersion': 1,
      'encodedPackageCiphertext': 'opaque',
    };
    var packageCalls = 0;
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'currentKeyEpoch': {'manifestSigningKeyVersion': 5},
        'memberVaultKey': <String, dynamic>{},
        'vaultPrivateKeys': [
          {
            'descriptor': {'purpose': 4},
          },
        ],
      },
    );
    when(
      () => vaultKeys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => vaultKeys.openCanonicalManifestSigningPrivateKey(
        any(),
        any(),
        expectedKeyVersion: any(named: 'expectedKeyVersion'),
      ),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((invocation) async {
      final expected = invocation.namedArguments[#expected]! as EntryEntity;
      return CanonicalEntrySnapshot(
        entry: {
          'id': expected.id,
          'organizationId': organizationId,
          'vaultId': vaultId,
          'currentRevision': '7',
        },
        payload: {
          'script': 'echo ok',
          'interpreter': 'bash',
          'refs': [
            for (var index = 0; index < refIds.length; index++)
              ScriptRef(
                env: 'REF_$index',
                vaultId: vaultId,
                entryId: refIds[index],
                field: 'key.value',
              ).toJson(),
          ],
          'execution': const ScriptExecutionMetadata(
            description: 'Four-ref test',
            returnResultToAgent: true,
          ).toJson(),
        },
        secret: {
          'entryType': EntryType.script.toWire(),
          'memberLabel': 'Script',
        },
      );
    });
    when(
      () => canonical.projectGrantFields(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        fieldIds: any(named: 'fieldIds'),
      ),
    ).thenAnswer((invocation) async {
      final expected = invocation.namedArguments[#expected]! as EntryEntity;
      return CanonicalGrantFieldProjection(
        entryId: expected.id,
        entryRevision: '3',
        fieldIds: const ['key.value'],
        encodedGrantPayload: Uint8List.fromList(
          utf8.encode(
            '{"entryType":"key","fields":[{"id":"key.value","kind":"concealed","mode":"value","value":"secret"}],"schema":"palladin.grant-payload.v1"}',
          ),
        ),
      );
    });
    when(
      () => packages.seal(
        grantId: any(named: 'grantId'),
        packageRevision: any(named: 'packageRevision'),
        agentId: any(named: 'agentId'),
        agentAccessEpoch: any(named: 'agentAccessEpoch'),
        agentPublicKey: any(named: 'agentPublicKey'),
        recipientAgentKeyVersion: any(named: 'recipientAgentKeyVersion'),
        vaultSigningKeyVersion: any(named: 'vaultSigningKeyVersion'),
        vaultSigningPrivateKey: any(named: 'vaultSigningPrivateKey'),
        scriptEntry: any(named: 'scriptEntry'),
        scriptPayload: any(named: 'scriptPayload'),
        referencedEntries: any(named: 'referencedEntries'),
      ),
    ).thenAnswer((invocation) async {
      packageCalls++;
      final refs =
          invocation.namedArguments[#referencedEntries]!
              as List<ScriptExecutionPackageEntryInput>;
      expect(refs, hasLength(4));
      return package;
    });
    when(
      () => approval.createGrant(
        vaultId: any(named: 'vaultId'),
        grantId: any(named: 'grantId'),
        agentId: any(named: 'agentId'),
        type: any(named: 'type'),
        scriptEntryId: any(named: 'scriptEntryId'),
        scriptPackage: any(named: 'scriptPackage'),
        expiresAt: any(named: 'expiresAt'),
        queryLimit: any(named: 'queryLimit'),
        methods: any(named: 'methods'),
      ),
    ).thenAnswer((_) async => 'grant-id');

    final repository = ApprovalRepositoryImpl(
      approvalDatasource: approval,
      entryDatasource: _Entries(),
      vaultDatasource: vaults,
      cryptoService: _Crypto(),
      vaultKeys: vaultKeys,
      canonicalEntries: canonical,
      discovery: _Discovery(),
      scriptPackages: packages,
    );
    await repository.createGrant(
      vaultId: vaultId,
      agentId: agentId,
      agentPublicKey: base64.encode(List<int>.filled(32, 9)),
      recipientKeyVersion: 4,
      agentAccessEpoch: 3,
      isFull: false,
      isScriptExecution: true,
      entryId: scriptId,
      privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
      limit: const GrantLifetime(),
      methods: const [GrantMethod.exec],
    );

    expect(packageCalls, 1);
    verify(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
    verify(
      () => canonical.projectGrantFields(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        fieldIds: any(named: 'fieldIds'),
      ),
    ).called(4);
    verify(
      () => approval.createGrant(
        vaultId: vaultId,
        grantId: any(named: 'grantId'),
        agentId: agentId,
        type: 'scriptExecution',
        scriptEntryId: scriptId,
        scriptPackage: package,
        expiresAt: null,
        queryLimit: null,
        methods: 'Exec',
      ),
    ).called(1);
  });

  test('Script cannot fall back to a granular grant', () async {
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const scriptId = '33333333-3333-4333-8333-333333333333';
    final approval = _Approval();
    final canonical = _Canonical();
    when(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => CanonicalEntrySnapshot(
        entry: {
          'organizationId': '11111111-1111-4111-8111-111111111111',
          'currentRevision': '7',
          'memberKeyGeneration': 3,
        },
        payload: {'script': 'echo safe'},
        secret: {
          'entryType': EntryType.script.toWire(),
          'memberLabel': 'Script',
        },
      ),
    );
    final repository = ApprovalRepositoryImpl(
      approvalDatasource: approval,
      entryDatasource: _Entries(),
      vaultDatasource: _Vaults(),
      cryptoService: _Crypto(),
      vaultKeys: _VaultKeys(),
      canonicalEntries: canonical,
      discovery: _Discovery(),
      scriptPackages: _Packages(),
    );

    await expectLater(
      repository.createGrant(
        vaultId: vaultId,
        agentId: '55555555-5555-4555-8555-555555555555',
        agentPublicKey: base64.encode(List<int>.filled(32, 9)),
        recipientKeyVersion: 4,
        agentAccessEpoch: 3,
        isFull: false,
        entryId: scriptId,
        privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
        limit: const GrantLifetime(),
        methods: const [GrantMethod.exec],
      ),
      throwsA(
        isA<ApprovalException>().having(
          (error) => error.kind,
          'kind',
          ApprovalErrorKind.validation,
        ),
      ),
    );
    verifyNever(
      () => approval.createGrant(
        vaultId: any(named: 'vaultId'),
        grantId: any(named: 'grantId'),
        agentId: any(named: 'agentId'),
        type: any(named: 'type'),
        entryId: any(named: 'entryId'),
        entries: any(named: 'entries'),
        expiresAt: any(named: 'expiresAt'),
        queryLimit: any(named: 'queryLimit'),
        methods: any(named: 'methods'),
      ),
    );
  });
}
