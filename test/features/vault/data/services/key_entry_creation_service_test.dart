import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/key_entry_creation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Envelopes extends Mock implements VaultEnvelopeCryptography {}

void main() {
  const vaultId = '22222233-4455-4677-8899-aabbccddeeff';
  const entryId = '33333344-5566-4788-99aa-bbccddeeff00';
  late _Entries entries;
  late _Vaults vaults;
  late _Keys keys;
  late _Envelopes envelopes;
  late Uint8List generatedDek;
  late Map<VaultAadProfile, String> openedPlaintexts;

  setUpAll(() {
    registerFallbackValue(VaultAadProfile.memberIndex);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    entries = _Entries();
    vaults = _Vaults();
    keys = _Keys();
    envelopes = _Envelopes();
    generatedDek = Uint8List(32)..fillRange(0, 32, 7);
    openedPlaintexts = {};
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'organizationId': '00112233-4455-4677-8899-aabbccddeeff',
        'memberKeyGeneration': 3,
        'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 5},
        'memberVaultKey': <String, dynamic>{},
        'discoveryKey': <String, dynamic>{},
      },
    );
    when(
      () => entries.issueCreationChallenge(vaultId),
    ).thenAnswer((_) async => entryId);
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => keys.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => envelopes.encrypt(
        profile: any(named: 'profile'),
        context: any(named: 'context'),
        plaintext: any(named: 'plaintext'),
        key: any(named: 'key'),
      ),
    ).thenAnswer((invocation) async {
      openedPlaintexts[invocation.namedArguments[#profile] as VaultAadProfile] =
          utf8.decode(invocation.namedArguments[#plaintext] as Uint8List);
      return {'nonce': 'opaque-nonce', 'ciphertext': 'opaque-ciphertext'};
    });
    when(
      () => entries.createCanonicalEntry(vaultId, any()),
    ).thenAnswer((_) async => {'id': entryId, 'currentRevision': '1'});
  });

  test(
    'uploads all Key projections in one ciphertext-only atomic request',
    () async {
      final service = KeyEntryCreationService(
        entries: entries,
        vaults: vaults,
        keys: keys,
        envelopes: envelopes,
        randomEntryKey: () async => generatedDek,
      );
      await service.create(
        vaultId: vaultId,
        label: 'Production API',
        description: 'sensitive note',
        icon: 'key',
        content: {'type': 'KEY', 'value': 'super-secret'},
        memberPrivateKey: Uint8List(32),
      );

      final payload =
          verify(
                () => entries.createCanonicalEntry(vaultId, captureAny()),
              ).captured.single
              as Map<String, dynamic>;
      expect(
        payload.keys,
        containsAll([
          'entryKey',
          'memberIndex',
          'memberSecret',
          'agentDiscovery',
          'grantEnvelopes',
        ]),
      );
      expect(payload.toString(), isNot(contains('super-secret')));
      expect(payload.toString(), isNot(contains('Production API')));
      expect(payload['entryId'], entryId);
      expect(generatedDek, everyElement(0));
    },
  );

  test('network failure still wipes the generated Entry DEK', () async {
    when(
      () => entries.createCanonicalEntry(vaultId, any()),
    ).thenThrow(Exception('offline'));
    final service = KeyEntryCreationService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      envelopes: envelopes,
      randomEntryKey: () async => generatedDek,
    );
    await expectLater(
      service.create(
        vaultId: vaultId,
        label: 'Key',
        description: '',
        icon: '',
        content: {'type': 'KEY', 'value': 'secret'},
        memberPrivateKey: Uint8List(32),
      ),
      throwsException,
    );
    expect(generatedDek, everyElement(0));
  });

  test('lost response retries the exact same atomic transition', () async {
    final requests = <Map<String, dynamic>>[];
    var attempt = 0;
    when(() => entries.createCanonicalEntry(vaultId, any())).thenAnswer((
      call,
    ) async {
      requests.add(call.positionalArguments[1] as Map<String, dynamic>);
      if (attempt++ == 0) {
        throw DioException(
          requestOptions: RequestOptions(path: '/entries'),
          type: DioExceptionType.connectionError,
        );
      }
      return {'id': entryId, 'currentRevision': '1'};
    });
    final service = KeyEntryCreationService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      envelopes: envelopes,
      randomEntryKey: () async => generatedDek,
    );
    await service.create(
      vaultId: vaultId,
      label: 'Key',
      description: '',
      icon: '',
      content: {'type': 'KEY', 'value': 'secret'},
      memberPrivateKey: Uint8List(32),
    );
    expect(requests, hasLength(2));
    expect(identical(requests[0], requests[1]), isTrue);
    expect(requests[0]['entryId'], entryId);
  });

  test(
    'Credential policy keeps password and TOTP seed out of Discovery',
    () async {
      final service = KeyEntryCreationService(
        entries: entries,
        vaults: vaults,
        keys: keys,
        envelopes: envelopes,
        randomEntryKey: () async => generatedDek,
      );
      await service.createCredential(
        vaultId: vaultId,
        label: 'Login',
        description: 'private note',
        icon: 'login',
        content: {
          'v': 2,
          'type': 'CREDENTIAL',
          'username': 'agent@example.com',
          'password': 'do-not-disclose',
          'url': 'https://Console.Example.com/path',
          'fields': [
            {'id': 'totp-1', 'type': 'totp', 'value': 'JBSWY3DPEHPK3PXP'},
          ],
        },
        memberPrivateKey: Uint8List(32),
        exposeUsername: false,
        exposeDomain: true,
      );
      final discovery = openedPlaintexts[VaultAadProfile.agentDiscovery]!;
      final secret = openedPlaintexts[VaultAadProfile.memberSecret]!;
      expect(discovery, contains('console.example.com'));
      expect(discovery, isNot(contains('agent@example.com')));
      expect(discovery, isNot(contains('do-not-disclose')));
      expect(discovery, isNot(contains('JBSWY3DPEHPK3PXP')));
      expect(secret, contains('JBSWY3DPEHPK3PXP'));
      expect(secret, contains('"totp":"onGrantDerived"'));
    },
  );

  test(
    'Credential validation fails closed before challenge issuance',
    () async {
      final service = KeyEntryCreationService(
        entries: entries,
        vaults: vaults,
        keys: keys,
        envelopes: envelopes,
        randomEntryKey: () async => generatedDek,
      );
      await expectLater(
        service.createCredential(
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
    },
  );
}
