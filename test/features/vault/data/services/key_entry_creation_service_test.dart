import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/key_entry_creation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _VaultCrypto extends Mock implements VaultCryptoService {}

class _EntryCrypto extends Mock implements EntryV2CryptoService {}

void main() {
  const vaultId = '22222233-4455-4677-8899-aabbccddeeff';
  const entryId = '33333344-5566-4788-99aa-bbccddeeff00';
  late _Entries entries;
  late _Vaults vaults;
  late _VaultCrypto vaultCrypto;
  late _EntryCrypto entryCrypto;
  late Uint8List vaultKey;
  late Uint8List discoveryKey;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      MemberSecret(
        entryType: VaultEntryType.key,
        memberLabel: 'fallback',
        agentLabel: 'fallback',
        description: null,
        icon: null,
        color: null,
        discoverable: true,
        content: const KeySecretContent(
          value: '',
          notes: null,
          customFields: [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.discovery,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.discovery,
          'key.value': AgentFieldAccess.onGrantValue,
          'notes': AgentFieldAccess.onGrantValue,
        },
      ),
    );
  });

  setUp(() {
    entries = _Entries();
    vaults = _Vaults();
    vaultCrypto = _VaultCrypto();
    entryCrypto = _EntryCrypto();
    vaultKey = Uint8List(32)..fillRange(0, 32, 4);
    discoveryKey = Uint8List(32)..fillRange(0, 32, 5);
    when(
      () => vaults.getEncryptedVault(vaultId),
    ).thenAnswer((_) async => {'opaque': true});
    when(
      () => entries.issueCreationChallenge(vaultId),
    ).thenAnswer((_) async => entryId);
    when(
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => OpenedVaultProjection(
        organizationId: '00112233-4455-4677-8899-aabbccddeeff',
        vaultId: vaultId,
        vaultKey: vaultKey,
        vaultDiscoveryKey: discoveryKey,
        metadata: const MemberVaultMetadata(
          name: 'Vault',
          description: null,
          icon: null,
          color: null,
          grantMode: 'full',
        ),
        epoch: const VaultKeyEpochModel(
          vaultKeyVersion: 4,
          vdkVersion: 5,
          agentMessageKeyVersion: 1,
          manifestSigningKeyVersion: 1,
        ),
        memberKeyGeneration: 3,
        wrapper: const MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: 'x',
          wrappedKeyVersion: 4,
          memberKeyGeneration: 3,
          recipientKeyVersion: 1,
          recipientFingerprint: 'fp',
        ),
      ),
    );
    when(
      () => entryCrypto.seal(
        organizationId: any(named: 'organizationId'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        revision: any(named: 'revision'),
        vaultKeyVersion: any(named: 'vaultKeyVersion'),
        vdkVersion: any(named: 'vdkVersion'),
        memberKeyGeneration: any(named: 'memberKeyGeneration'),
        operation: any(named: 'operation'),
        secret: any(named: 'secret'),
        vaultKey: any(named: 'vaultKey'),
        vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
      ),
    ).thenAnswer(
      (_) async => const EntryEnvelopeBundleModel(
        entryKey: {'descriptor': 'entry'},
        memberIndex: {'descriptor': 'index'},
        memberSecret: {'descriptor': 'secret'},
        agentDiscovery: {'descriptor': 'discovery'},
      ),
    );
    when(
      () => entries.createCanonicalEntry(vaultId, any()),
    ).thenAnswer((_) async => {});
  });

  KeyEntryCreationService service() => KeyEntryCreationService(
    entries: entries,
    vaults: vaults,
    vaultCrypto: vaultCrypto,
    entryCrypto: entryCrypto,
  );

  test('uses canonical projection opener and Entry v2 sealer', () async {
    final privateKey = Uint8List(32)..fillRange(0, 32, 9);
    await service().create(
      vaultId: vaultId,
      label: 'Production API',
      description: '',
      icon: 'key',
      content: {'type': 'KEY', 'value': 'super-secret'},
      memberPrivateKey: privateKey,
    );
    final request =
        verify(
              () => entries.createCanonicalEntry(vaultId, captureAny()),
            ).captured.single
            as Map<String, Object?>;
    expect(request['entryId'], entryId);
    expect(request.toString(), isNot(contains('super-secret')));
    verify(
      () => entryCrypto.seal(
        entryId: entryId,
        organizationId: any(named: 'organizationId'),
        vaultId: vaultId,
        revision: 1,
        vaultKeyVersion: 4,
        vdkVersion: 5,
        memberKeyGeneration: 3,
        operation: 1,
        secret: any(named: 'secret'),
        vaultKey: any(named: 'vaultKey'),
        vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
      ),
    ).called(1);
    expect(privateKey, everyElement(9));
    expect(vaultKey, everyElement(0));
    expect(discoveryKey, everyElement(0));
  });

  test(
    'lost response retries the byte-identical canonical transition',
    () async {
      final requests = <Object?>[];
      var attempt = 0;
      when(() => entries.createCanonicalEntry(vaultId, any())).thenAnswer((
        call,
      ) async {
        requests.add(call.positionalArguments[1]);
        if (attempt++ == 0) {
          throw DioException(
            requestOptions: RequestOptions(path: '/entries'),
            type: DioExceptionType.connectionError,
          );
        }
        return {};
      });
      await service().create(
        vaultId: vaultId,
        label: 'Key',
        description: '',
        icon: '',
        content: {'type': 'KEY', 'value': 'secret'},
        memberPrivateKey: Uint8List(32),
      );
      expect(requests, hasLength(2));
      expect(identical(requests[0], requests[1]), isTrue);
      verify(
        () => entryCrypto.seal(
          organizationId: any(named: 'organizationId'),
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          revision: any(named: 'revision'),
          vaultKeyVersion: any(named: 'vaultKeyVersion'),
          vdkVersion: any(named: 'vdkVersion'),
          memberKeyGeneration: any(named: 'memberKeyGeneration'),
          operation: any(named: 'operation'),
          secret: any(named: 'secret'),
          vaultKey: any(named: 'vaultKey'),
          vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
        ),
      ).called(1);
    },
  );

  test('malformed credential fails before challenge or crypto', () async {
    await expectLater(
      service().createCredential(
        vaultId: vaultId,
        label: 'Bad',
        description: '',
        icon: '',
        content: {'type': 'CREDENTIAL', 'username': 'u'},
        memberPrivateKey: Uint8List(32),
        exposeUsername: true,
        exposeDomain: true,
      ),
      throwsFormatException,
    );
    verifyNever(() => entries.issueCreationChallenge(vaultId));
    verifyNever(
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    );
  });
}
