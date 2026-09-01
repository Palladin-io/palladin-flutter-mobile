import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Grants extends Mock implements GrantsRemoteDatasource {}

class _RestoreCryptography implements VaultEnvelopeCryptography {
  final encrypted =
      <({VaultAadProfile profile, Map<String, Object?> context})>[];
  final issuedPlaintexts = <Uint8List>[];

  final Uint8List _secret = VaultProtocolBytes.utf8Encode(
    canonicalizeVaultJson({
      'agentLabel': 'Agent label',
      'agentVisibilityPolicy': {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'username': 'discovery'},
      },
      'content': {
        'type': 'CREDENTIAL',
        'username': 'member@example.test',
        'password': 'never-on-wire',
      },
      'entryType': 1,
      'memberLabel': 'Archived login',
      'schemaVersion': 1,
    }),
  );

  @override
  Future<Uint8List> decrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> envelope,
    required Uint8List key,
    required VaultEnvelopeExpectations expected,
  }) async {
    final value = profile == VaultAadProfile.entryKeyWrapper
        ? Uint8List.fromList(List<int>.filled(32, 9))
        : Uint8List.fromList(_secret);
    issuedPlaintexts.add(value);
    return value;
  }

  @override
  Future<Map<String, String>> encrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> context,
    required Uint8List plaintext,
    required Uint8List key,
  }) async {
    encrypted.add((profile: profile, context: Map.from(context)));
    return {'nonce': _b64(24), 'ciphertext': _b64(32)};
  }

  @override
  Future<Uint8List> randomKey() async => Uint8List(32);

  @override
  Future<Uint8List> sealPackage({
    required Uint8List packageBytes,
    required Uint8List recipientPublicKey,
  }) async => Uint8List(80);
}

String _b64(int length) => base64Url
    .encode(List<int>.generate(length, (index) => index))
    .replaceAll('=', '');

void main() {
  const organizationId = '11111111-1111-4111-8111-111111111111';
  const vaultId = '22222222-2222-4222-8222-222222222222';
  const entryId = '33333333-3333-4333-8333-333333333333';
  const archived = MemberIndexEntry(
    entryId: entryId,
    entryType: 1,
    memberLabel: 'Archived login',
    searchFields: ['member@example.test', 'example.test'],
    revision: '7',
    currentKeyVersion: 2,
    state: MemberEntryState.archived,
  );
  const deleted = MemberIndexEntry(
    entryId: entryId,
    entryType: 1,
    memberLabel: 'Deleted login',
    searchFields: ['member@example.test'],
    revision: '7',
    currentKeyVersion: 2,
    state: MemberEntryState.deleted,
  );

  late _Entries entries;
  late _Vaults vaults;
  late _Keys keys;
  late _RestoreCryptography cryptography;
  late AutoFillMutationNotifier autoFillMutationNotifier;
  late List<AutoFillMutationAction> autoFillActions;
  late CanonicalEntryDetailService service;

  Map<String, dynamic> header(int projection, int keyVersion) => {
    'protocolVersion': 2,
    'algorithmSuite': 1,
    'resourceKind': 2,
    'projectionKind': projection,
    'resourceRevision': '7',
    'keyVersion': keyVersion,
    'memberKeyGeneration': 3,
    'nonce': _b64(24),
  };

  Map<String, dynamic> canonicalEntry() => {
    'organizationId': organizationId,
    'vaultId': vaultId,
    'id': entryId,
    'state': 2,
    'currentRevision': '7',
    'memberIndexRevision': '3',
    'agentDiscoveryRevisionHighWatermark': '5',
    'currentKeyVersion': 2,
    'entryKey': {
      'organizationId': organizationId,
      'vaultId': vaultId,
      'entryId': entryId,
      'wrapperRevision': '1',
      'keyVersion': 2,
      'memberKeyGeneration': 3,
      'wrappingKeyVersion': 4,
      'header': header(8, 2),
      'wrappedEntryDekByVk': _b64(32),
    },
    'memberSecret': {
      'organizationId': organizationId,
      'vaultId': vaultId,
      'entryId': entryId,
      'revision': '7',
      'operation': 3,
      'header': header(3, 2),
      'ciphertext': _b64(32),
    },
  };

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(Uint8List(32));
  });

  setUp(() {
    entries = _Entries();
    vaults = _Vaults();
    keys = _Keys();
    cryptography = _RestoreCryptography();
    autoFillMutationNotifier = AutoFillMutationNotifier();
    autoFillActions = [];
    final subscription = autoFillMutationNotifier.changes.listen(
      autoFillActions.add,
    );
    addTearDown(subscription.cancel);
    service = CanonicalEntryDetailService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      envelopes: cryptography,
      grants: _Grants(),
      autoFillMutationNotifier: autoFillMutationNotifier,
    );
    when(
      () => entries.getCanonicalEntry(vaultId, entryId),
    ).thenAnswer((_) async => canonicalEntry());
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'organizationId': organizationId,
        'memberKeyGeneration': 3,
        'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 6},
        'memberVaultKey': <String, dynamic>{},
        'discoveryKey': <String, dynamic>{},
      },
    );
    when(
      () => keys.openMemberVaultKey(
        any(),
        any(),
        expectedOrganizationId: any(named: 'expectedOrganizationId'),
        expectedVaultId: any(named: 'expectedVaultId'),
        expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
        expectedMemberKeyGeneration: any(named: 'expectedMemberKeyGeneration'),
      ),
    ).thenAnswer((_) async => Uint8List.fromList(List<int>.filled(32, 1)));
    when(
      () => keys.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList(List<int>.filled(32, 2)));
  });

  test('builds scoped Restored projections at the next revisions', () async {
    Map<String, dynamic>? request;
    when(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer((invocation) async {
      request = invocation.positionalArguments[2] as Map<String, dynamic>;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/restore'),
        statusCode: 200,
      );
    });

    await service.restoreArchived(
      vaultId: vaultId,
      archived: archived,
      memberPrivateKey: Uint8List(32),
    );

    expect(request?['baseRevision'], '7');
    final secret = request?['memberSecret'] as Map;
    final index = request?['memberIndex'] as Map;
    final discovery = request?['agentDiscovery'] as Map;
    expect((secret['revision'], secret['operation']), ('8', 4));
    expect(index['memberIndexRevision'], '4');
    expect(discovery['agentDiscoveryRevision'], '6');
    for (final envelope in [secret, index, discovery]) {
      expect(
        (envelope['organizationId'], envelope['vaultId'], envelope['entryId']),
        (organizationId, vaultId, entryId),
      );
    }
    expect(
      cryptography.encrypted.map((item) => item.profile),
      containsAllInOrder([
        VaultAadProfile.memberSecret,
        VaultAadProfile.memberIndex,
        VaultAadProfile.agentDiscovery,
      ]),
    );
    expect(cryptography.issuedPlaintexts, everyElement(everyElement(0)));
    expect(autoFillActions, [
      AutoFillMutationAction.invalidate,
      AutoFillMutationAction.rebuild,
    ]);
  });

  test('ambiguous transport retry reuses the exact prepared payload', () async {
    final requests = <Map<String, dynamic>>[];
    when(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer((invocation) async {
      requests.add(invocation.positionalArguments[2] as Map<String, dynamic>);
      if (requests.length == 1) {
        throw DioException(
          requestOptions: RequestOptions(path: '/restore'),
          type: DioExceptionType.connectionError,
        );
      }
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/restore'),
        statusCode: 200,
      );
    });

    await service.restoreArchived(
      vaultId: vaultId,
      archived: archived,
      memberPrivateKey: Uint8List(32),
    );

    expect(requests, hasLength(2));
    expect(identical(requests.first, requests.last), isTrue);
    expect(
      canonicalizeVaultJson(requests.first),
      canonicalizeVaultJson(requests.last),
    );
    expect(autoFillActions, [
      AutoFillMutationAction.invalidate,
      AutoFillMutationAction.rebuild,
    ]);
  });

  test('409 is an explicit conflict and is not retried', () async {
    when(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/restore'),
        statusCode: 409,
      ),
    );

    await expectLater(
      service.restoreArchived(
        vaultId: vaultId,
        archived: archived,
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.conflict,
        ),
      ),
    );
    verify(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).called(1);
    expect(autoFillActions, [
      AutoFillMutationAction.invalidate,
      AutoFillMutationAction.rebuild,
    ]);
  });

  test('ambiguous restore failure leaves AutoFill invalidated', () async {
    when(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/restore'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      service.restoreArchived(
        vaultId: vaultId,
        archived: archived,
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.network,
        ),
      ),
    );

    verify(
      () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
    ).called(2);
    expect(autoFillActions, [AutoFillMutationAction.invalidate]);
  });

  test(
    'Deleted restore uses the same Restored pipeline and validates state',
    () async {
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => {...canonicalEntry(), 'state': 3});
      when(
        () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/restore'),
          statusCode: 200,
        ),
      );
      await service.restoreRecoverable(
        vaultId: vaultId,
        entry: deleted,
        memberPrivateKey: Uint8List(32),
      );

      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => canonicalEntry());
      await expectLater(
        service.restoreRecoverable(
          vaultId: vaultId,
          entry: deleted,
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.corrupt,
          ),
        ),
      );
    },
  );

  test(
    'purge sends no secret, treats 404 as idempotent, and maps 409',
    () async {
      when(() => entries.destroyEntry(vaultId, entryId)).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/destroy'),
          statusCode: 404,
        ),
      );
      await service.purgeDeleted(vaultId: vaultId, entryId: entryId);
      verify(() => entries.destroyEntry(vaultId, entryId)).called(1);
      verifyNever(() => entries.getCanonicalEntry(any(), any()));
      expect(autoFillActions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);

      reset(entries);
      autoFillActions.clear();
      when(() => entries.destroyEntry(vaultId, entryId)).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: '/destroy'),
          statusCode: 409,
        ),
      );
      await expectLater(
        service.purgeDeleted(vaultId: vaultId, entryId: entryId),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.conflict,
          ),
        ),
      );
      expect(autoFillActions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test('ambiguous purge failure leaves AutoFill invalidated', () async {
    when(() => entries.destroyEntry(vaultId, entryId)).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/destroy'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      service.purgeDeleted(vaultId: vaultId, entryId: entryId),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.network,
        ),
      ),
    );

    verify(() => entries.destroyEntry(vaultId, entryId)).called(2);
    expect(autoFillActions, [AutoFillMutationAction.invalidate]);
  });

  test('cache clear failure is typed and blocks permanent purge', () async {
    autoFillMutationNotifier.attachHandler((action) async {
      if (action == AutoFillMutationAction.invalidate) {
        throw StateError('native clear failed');
      }
    });
    addTearDown(autoFillMutationNotifier.detachHandler);

    await expectLater(
      service.purgeDeleted(vaultId: vaultId, entryId: entryId),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.network,
        ),
      ),
    );

    verifyNever(() => entries.destroyEntry(any(), any()));
    expect(autoFillActions, [AutoFillMutationAction.invalidate]);
  });
}
