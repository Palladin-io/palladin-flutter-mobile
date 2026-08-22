import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
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
  late AutoFillMutationNotifier autoFillMutationNotifier;
  late List<AutoFillMutationAction> autoFillActions;
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
    autoFillMutationNotifier = AutoFillMutationNotifier();
    autoFillActions = [];
    final subscription = autoFillMutationNotifier.changes.listen(
      autoFillActions.add,
    );
    addTearDown(subscription.cancel);
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
    autoFillMutationNotifier: autoFillMutationNotifier,
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
    expect(request.containsKey('entryType'), isFalse);
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
    expect(autoFillActions, [
      AutoFillMutationAction.invalidate,
      AutoFillMutationAction.rebuild,
    ]);
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
      expect(autoFillActions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test('ambiguous create failure leaves AutoFill invalidated', () async {
    when(() => entries.createCanonicalEntry(vaultId, any())).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/entries'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      service().create(
        vaultId: vaultId,
        label: 'Key',
        description: '',
        icon: '',
        content: {'type': 'KEY', 'value': 'secret'},
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(isA<DioException>()),
    );

    verify(() => entries.createCanonicalEntry(vaultId, any())).called(2);
    expect(autoFillActions, [AutoFillMutationAction.invalidate]);
  });

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
    expect(autoFillActions, isEmpty);
    verifyNever(() => entries.issueCreationChallenge(vaultId));
    verifyNever(
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    );
  });

  test(
    'retired dedicated card fields fail before challenge or crypto',
    () async {
      for (final retired in const {
        'securityCode': '123',
        'pin': '4321',
      }.entries) {
        await expectLater(
          service().createCreditCard(
            vaultId: vaultId,
            label: 'Legacy card',
            description: '',
            icon: '',
            content: {
              'type': 'CREDIT_CARD',
              'cardholderName': 'Ada Lovelace',
              'cardNumber': '4242424242424242',
              'expiryMonth': '12',
              'expiryYear': '2030',
              retired.key: retired.value,
            },
            memberPrivateKey: Uint8List(32),
          ),
          throwsFormatException,
        );
      }
      verifyNever(() => entries.issueCreationChallenge(vaultId));
      verifyNever(
        () => vaultCrypto.openVaultProjection(
          json: any(named: 'json'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      );
    },
  );

  test(
    'persists create-form Discovery choices in the first revision',
    () async {
      await service().createCredential(
        vaultId: vaultId,
        label: 'Mailbox',
        description: 'Operations account',
        icon: '',
        content: {
          'type': 'CREDENTIAL',
          'username': 'operator',
          'password': 'secret',
          'url': 'https://mail.example.com/login',
        },
        memberPrivateKey: Uint8List(32),
        exposeUsername: true,
        exposeDomain: false,
        discoverDescription: true,
      );

      final secret =
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
                  secret: captureAny(named: 'secret'),
                  vaultKey: any(named: 'vaultKey'),
                  vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
                ),
              ).captured.single
              as MemberSecret;

      expect(secret.agentFieldAccess['agentLabel'], AgentFieldAccess.discovery);
      expect(
        secret.agentFieldAccess['description'],
        AgentFieldAccess.discovery,
      );
      expect(
        secret.agentFieldAccess['credential.username'],
        AgentFieldAccess.discovery,
      );
      expect(
        secret.agentFieldAccess['credential.urlDomain'],
        AgentFieldAccess.never,
      );
    },
  );

  test('keeps credit-card custom text fields runtime-only', () async {
    const customId = '44444455-6677-4889-9aab-ccddeeff0011';
    await service().createCreditCard(
      vaultId: vaultId,
      label: 'Travel card',
      description: '',
      icon: '',
      content: {
        'type': 'CREDIT_CARD',
        'cardholderName': 'Patryk',
        'cardNumber': '4111111111111111',
        'expiryMonth': '12',
        'expiryYear': '2030',
        'fields': [
          {
            'id': customId,
            'label': 'Account number',
            'type': 'text',
            'value': 'private-account-number',
            'agentVisible': true,
          },
        ],
      },
      memberPrivateKey: Uint8List(32),
    );

    final secret =
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
                secret: captureAny(named: 'secret'),
                vaultKey: any(named: 'vaultKey'),
                vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
              ),
            ).captured.single
            as MemberSecret;

    expect(
      secret.agentFieldAccess['custom:$customId'],
      AgentFieldAccess.onGrantRuntime,
    );
    expect(
      VaultPlaintextProjector.agentDiscovery(secret).toString(),
      isNot(contains('private-account-number')),
    );
  });
}
