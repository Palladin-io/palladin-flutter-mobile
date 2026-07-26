import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}
class _Vaults extends Mock implements VaultRemoteDatasource {}
class _Keys extends Mock implements VaultRotationCryptoService {}

class _RecordingEnvelopes implements VaultEnvelopeCryptography {
  final encrypted = <({VaultAadProfile profile, Map<String, Object?> context, Uint8List plaintext})>[];

  @override
  Future<Uint8List> decrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> envelope,
    required Uint8List key,
    required VaultEnvelopeExpectations expected,
  }) async => Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<Map<String, String>> encrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> context,
    required Uint8List plaintext,
    required Uint8List key,
  }) async {
    encrypted.add((
      profile: profile,
      context: Map<String, Object?>.from(context),
      plaintext: Uint8List.fromList(plaintext),
    ));
    return {'nonce': _b64(24), 'ciphertext': _b64(32)};
  }
}

String _b64(int length) => base64Url
    .encode(List<int>.generate(length, (index) => index))
    .replaceAll('=', '');

void main() {
  const organizationId = '11111111-1111-4111-8111-111111111111';
  const vaultId = '22222222-2222-4222-8222-222222222222';
  const entryId = '33333333-3333-4333-8333-333333333333';
  final entry = EntryEntity(
    id: entryId,
    vaultId: vaultId,
    label: 'Old',
    type: EntryType.credential,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 2),
  );

  late _Entries entries;
  late _Vaults vaults;
  late _Keys keys;
  late _RecordingEnvelopes envelopes;
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
    'currentRevision': '7',
    'memberIndexRevision': '3',
    'agentDiscoveryRevision': '5',
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
      'operation': 1,
      'header': header(3, 2),
      'ciphertext': _b64(32),
    },
  };

  Map<String, dynamic> vault() => {
    'organizationId': organizationId,
    'memberKeyGeneration': 3,
    'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 6},
    'memberVaultKey': <String, dynamic>{},
    'discoveryKey': <String, dynamic>{},
  };

  CanonicalEntrySnapshot snapshot() => CanonicalEntrySnapshot(
    entry: canonicalEntry(),
    payload: {
      'type': 'CREDENTIAL',
      'username': 'old@example.com',
      'password': 'old-secret',
    },
    secret: {
      'schemaVersion': 1,
      'agentLabel': 'Agent label',
      'agentVisibilityPolicy': {
        'discoverable': true,
        'fields': {
          'username': 'discovery',
          'urlDomain': 'discovery',
          'password': 'onGrantValue',
        },
      },
    },
  );

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    entries = _Entries();
    vaults = _Vaults();
    keys = _Keys();
    envelopes = _RecordingEnvelopes();
    service = CanonicalEntryDetailService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      envelopes: envelopes,
    );
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer((_) async => vault());
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList(List<int>.filled(32, 1)));
    when(
      () => keys.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList(List<int>.filled(32, 2)));
  });

  test('emits one atomic N+1 update with all consistent projection heads', () async {
    Map<String, dynamic>? request;
    when(
      () => entries.updateCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer((invocation) async {
      request = invocation.positionalArguments[2] as Map<String, dynamic>;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/entries'),
        statusCode: 200,
        data: {'currentRevision': '8'},
      );
    });

    await service.update(
      snapshot: snapshot(),
      expected: entry,
      label: 'New label',
      description: 'Description',
      icon: 'key',
      type: EntryType.credential,
      content: {
        'type': 'CREDENTIAL',
        'username': 'new@example.com',
        'password': 'new-secret',
        'url': 'https://Example.com/login',
      },
      memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 7)),
    );

    expect(request?['baseRevision'], '7');
    expect((request?['memberSecret'] as Map)['revision'], '8');
    expect((request?['memberIndex'] as Map)['memberIndexRevision'], '4');
    expect(
      (request?['agentDiscovery'] as Map)['agentDiscoveryRevision'],
      '6',
    );
    expect(request?['agentDiscoveryChanged'], isTrue);
    expect(
      ((request?['memberSecret'] as Map)['header'] as Map)['resourceRevision'],
      '8',
    );
    expect(
      ((request?['memberIndex'] as Map)['header'] as Map)['resourceRevision'],
      '4',
    );
    expect(
      ((request?['agentDiscovery'] as Map)['header']
          as Map)['resourceRevision'],
      '6',
    );
    expect(request?['grantEnvelopes'], isEmpty);
    expect(
      envelopes.encrypted.map((value) => value.profile),
      containsAll({
        VaultAadProfile.memberSecret,
        VaultAadProfile.memberIndex,
        VaultAadProfile.agentDiscovery,
      }),
    );
    final discovery = envelopes.encrypted.singleWhere(
      (value) => value.profile == VaultAadProfile.agentDiscovery,
    );
    final discoveryJson = jsonDecode(utf8.decode(discovery.plaintext)) as Map;
    expect(discoveryJson['fields'], {
      'urlDomain': 'example.com',
      'username': 'new@example.com',
    });
    verify(
      () => entries.updateCanonicalEntry(vaultId, entryId, any()),
    ).called(1);
  });

  test('maps 409 to an explicit conflict without retrying', () async {
    when(
      () => entries.updateCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/entries'),
        statusCode: 409,
      ),
    );

    await expectLater(
      service.update(
        snapshot: snapshot(),
        expected: entry,
        label: 'New label',
        description: '',
        icon: '',
        type: EntryType.credential,
        content: {
          'type': 'CREDENTIAL',
          'username': 'new@example.com',
          'password': 'new-secret',
        },
        memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 7)),
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
      () => entries.updateCanonicalEntry(vaultId, entryId, any()),
    ).called(1);
  });

  test('rewraps the DEK and binds projections after generation advances', () async {
    final stale = snapshot();
    final wrapper = stale.entry['entryKey'] as Map<String, dynamic>;
    wrapper['memberKeyGeneration'] = 2;
    (wrapper['header'] as Map<String, dynamic>)['memberKeyGeneration'] = 2;
    Map<String, dynamic>? request;
    when(
      () => entries.updateCanonicalEntry(vaultId, entryId, any()),
    ).thenAnswer((invocation) async {
      request = invocation.positionalArguments[2] as Map<String, dynamic>;
      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/entries'),
        statusCode: 200,
        data: {'currentRevision': '8'},
      );
    });

    await service.update(
      snapshot: stale,
      expected: entry,
      label: 'New label',
      description: '',
      icon: '',
      type: EntryType.credential,
      content: {
        'type': 'CREDENTIAL',
        'username': 'new@example.com',
        'password': 'new-secret',
      },
      memberPrivateKey: Uint8List.fromList(List<int>.filled(32, 7)),
    );

    final newKey = request?['newEntryKey'] as Map;
    expect(newKey['keyVersion'], 3);
    expect(newKey['memberKeyGeneration'], 3);
    expect(
      ((request?['memberSecret'] as Map)['header'] as Map)['keyVersion'],
      3,
    );
    expect(
      envelopes.encrypted.map((value) => value.profile),
      contains(VaultAadProfile.entryKeyWrapper),
    );
  });
}
