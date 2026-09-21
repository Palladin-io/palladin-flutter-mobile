import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_copy_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_copy_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_copy_projection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_lifetime.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_copy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_copy_cubit.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Config extends Mock implements EnvConfig {}

class _Tokens extends Mock implements SecureTokenStorage {}

class _Sodium extends Mock implements SodiumSumo {}

class _Randombytes extends Mock implements Randombytes {}

class _ObservedVaultCrypto extends VaultCryptoService {
  _ObservedVaultCrypto(SodiumSumo sodium)
    : super(sodiumLoader: () async => sodium);
  Uint8List? privateCopy;
  OpenedVaultProjection? opened;
  Completer<void>? barrier;
  final entered = Completer<void>();
  @override
  Future<OpenedVaultProjection> openVaultProjection({
    required Map<String, dynamic> json,
    required Uint8List memberPrivateKey,
  }) async {
    privateCopy = memberPrivateKey;
    final result = await super.openVaultProjection(
      json: json,
      memberPrivateKey: memberPrivateKey,
    );
    opened = result;
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
    return result;
  }
}

const _vault = '22222222-2222-4222-8222-222222222222';
const _entry = '33333333-3333-4333-8333-333333333333';
const EntrySharingSession _owner = (
  principalId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationId: '11111111-1111-4111-8111-111111111111',
  authorizationGeneration: '7',
  keyGeneration: 1,
);
const _value = '  synthetic received password e\u0301\u0000  ';
String _jwt([Map<String, Object?> changes = const {}]) =>
    'header.${base64UrlEncode(utf8.encode(jsonEncode({'sub': _owner.principalId, 'org_id': _owner.organizationId, 'authz_ver': 7, ...changes})))}.signature';

final _snapshot = EntryShareSnapshot.fromJson({
  'schema': EntryShareSnapshot.schema,
  'title': 'Received credential',
  'entryType': 'credential',
  'fields': [
    {'id': 'credential.username', 'label': '', 'type': 'text', 'value': 'user'},
    {
      'id': 'credential.password',
      'label': '',
      'type': 'concealed',
      'value': _value,
    },
  ],
});

Matcher _failure(EntryShareCopyError kind) =>
    throwsA(isA<EntryShareCopyException>().having((e) => e.kind, 'kind', kind));

void main() {
  late SodiumSumo sodium;
  late HttpServer server;
  late _Tokens tokens;
  late VaultSessionStore keys;
  late Uint8List privateKey;
  late CreatedVaultBundle bundle;
  late Map<String, dynamic> vaultJson;
  late EntryShareCopyDatasource remote;
  late _ObservedVaultCrypto vaultCrypto;
  late EntryV2CryptoService entryCrypto;
  late EntryShareCopyService service;
  late AutoFillMutationNotifier notifier;
  late List<AutoFillMutationAction> cacheActions;
  late List<({String path, String method, String body, HttpHeaders headers})>
  requests;
  late Future<void> Function(HttpRequest) handler;
  late bool ownerValid;

  setUpAll(() async {
    final path = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = path != null || Platform.isLinux
        ? await sodium_ffi.SodiumSumoInit.init(
            () => DynamicLibrary.open(path ?? 'libsodium.so'),
          )
        : await SodiumSumoInit.init();
    SodiumProvider.debugOverride = sodium;
  });
  tearDownAll(() => SodiumProvider.debugOverride = null);

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final config = _Config();
    when(() => config.apiBaseUrl).thenReturn('http://127.0.0.1:${server.port}');
    when(() => config.certificatePins).thenReturn([]);
    tokens = _Tokens();
    when(() => tokens.accessToken).thenAnswer((_) async => _jwt());
    keys = VaultSessionStore();
    privateKey = sodium.randombytes.buf(32);
    keys.setMemberPrivateKey(privateKey);
    bundle = await VaultCryptoService(sodiumLoader: () async => sodium)
        .createVaultBundle(
          organizationId: _owner.organizationId,
          memberId: _owner.principalId,
          memberKeyVersion: 1,
          vaultId: _vault,
          memberPrivateKey: privateKey,
          name: 'Synthetic target vault',
          grantMode: GrantMode.granular,
        );
    vaultJson =
        jsonDecode(
              jsonEncode({
                'id': _vault,
                'organizationId': _owner.organizationId,
                'memberKeyGeneration': 1,
                'metadataRevision': '1',
                'memberVaultKey': {
                  'wrappedVaultKey': bundle.request.creatorVaultKey.toJson(),
                },
                'memberVaultMetadata': bundle.request.memberVaultMetadata
                    .toJson(),
                'discoveryKey': bundle.request.discoveryKey.toJson(),
                'currentKeyEpoch': bundle.request.currentKeyEpoch.toJson(),
              }),
            )
            as Map<String, dynamic>;
    remote = EntryShareCopyDatasource(config, tokens, keys);
    vaultCrypto = _ObservedVaultCrypto(sodium);
    entryCrypto = EntryV2CryptoService(sodiumLoader: () async => sodium);
    notifier = AutoFillMutationNotifier();
    cacheActions = [];
    notifier.attachHandler((action) async => cacheActions.add(action));
    service = EntryShareCopyService(
      remote: remote,
      vaultCrypto: vaultCrypto,
      entryCrypto: entryCrypto,
      autoFill: notifier,
    );
    requests = [];
    ownerValid = true;
    handler = (request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/vaults') {
        request.response.write(
          jsonEncode({
            'vaults': [
              Map<String, dynamic>.from(vaultJson)
                ..remove('organizationId')
                ..remove('metadataRevision'),
            ],
            'total': 1,
          }),
        );
      } else if (request.uri.path == '/api/vaults/$_vault') {
        request.response.write(jsonEncode(vaultJson));
      } else if (request.uri.path.endsWith('/creation-challenges')) {
        request.response.write(
          jsonEncode({
            'items': [
              {'entryId': _entry},
            ],
          }),
        );
      } else {
        request.response.statusCode = 204;
      }
      await request.response.close();
    };
    server.listen((request) async {
      requests.add((
        path: request.uri.toString(),
        method: request.method,
        body: await utf8.decoder.bind(request).join(),
        headers: request.headers,
      ));
      await handler(request);
    });
  });
  tearDown(() async {
    service.close();
    keys.clear();
    privateKey.fillRange(0, privateKey.length, 0);
    bundle.vaultKey.fillRange(0, bundle.vaultKey.length, 0);
    bundle.vaultDiscoveryKey.fillRange(0, bundle.vaultDiscoveryKey.length, 0);
    await server.close(force: true);
  });
  Future<PreparedEntryShareCopy> prepare({CancelToken? token}) =>
      service.prepare(
        snapshot: _snapshot,
        vaultId: _vault,
        owner: _owner,
        memberPrivateKey: privateKey,
        validateOwner: () async => ownerValid,
        cancelToken: token ?? CancelToken(),
      );
  Future<void> commit(PreparedEntryShareCopy copy, {CancelToken? token}) =>
      service.commit(
        copy,
        validateOwner: () async => ownerValid,
        cancelToken: token ?? CancelToken(),
      );

  Future<EntryShareCopyDestinations> destinations({CancelToken? token}) =>
      service.destinations(
        owner: _owner,
        memberPrivateKey: privateKey,
        validateOwner: () async => ownerValid,
        cancelToken: token ?? CancelToken(),
      );

  test(
    'destination list decrypts scoped summaries without detail fan-out or challenges',
    () async {
      final result = await destinations();
      expect(result.items.single.id, _vault);
      expect(result.items.single.name, 'Synthetic target vault');
      expect(result.unavailable, 0);
      expect(requests.single.path, '/api/vaults?limit=50&offset=0');
      expect(
        requests.single.headers.value('authorization'),
        'Bearer ${_jwt()}',
      );
      expect(vaultCrypto.privateCopy, everyElement(0));
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
      expect(vaultCrypto.opened!.vaultDiscoveryKey, everyElement(0));
    },
  );

  for (final field in ['organizationId', 'vaultId', 'memberId']) {
    test('destination list isolates substituted wrapper $field', () async {
      final corrupt = jsonDecode(jsonEncode(vaultJson)) as Map<String, dynamic>;
      corrupt['memberVaultKey']['wrappedVaultKey']['descriptor']['scope'][field] =
          _entry;
      handler = (request) async {
        request.response.write(
          jsonEncode({
            'vaults': [corrupt, vaultJson],
            'total': 2,
          }),
        );
        await request.response.close();
      };
      final result = await destinations();
      expect(result.items.single.id, _vault);
      expect(result.unavailable, 1);
      expect(requests.length, 1);
    });
  }

  test(
    'destination pagination stays bounded and deduplicates a moving page',
    () async {
      handler = (request) async {
        request.response.write(
          jsonEncode({
            'vaults': [vaultJson],
            'total': 2,
          }),
        );
        await request.response.close();
      };
      final result = await destinations();
      expect(result.items.length, 1);
      expect(requests.map((r) => r.path), [
        '/api/vaults?limit=50&offset=0',
        '/api/vaults?limit=50&offset=1',
      ]);
    },
  );

  for (final page in [
    {'vaults': [], 'total': 2001},
    {'vaults': [], 'total': 1},
  ]) {
    test(
      'destination list rejects exhausted or oversized work budget $page',
      () async {
        handler = (request) async {
          request.response.write(jsonEncode(page));
          await request.response.close();
        };
        await expectLater(
          destinations(),
          _failure(EntryShareCopyError.request),
        );
        expect(vaultCrypto.privateCopy, isNull);
        expect(requests.length, 1);
      },
    );
  }

  test(
    'destination cancellation wipes in-flight private copy and late Vault keys',
    () async {
      final token = CancelToken();
      final barrier = vaultCrypto.barrier = Completer<void>();
      final pending = destinations(token: token);
      final checked = expectLater(
        pending,
        _failure(EntryShareCopyError.cancelled),
      );
      await vaultCrypto.entered.future;
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(vaultCrypto.privateCopy, everyElement(0));
      barrier.complete();
      await checked;
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
      expect(vaultCrypto.opened!.vaultDiscoveryKey, everyElement(0));
    },
  );

  test(
    'destination owner change after decryption cannot publish names',
    () async {
      final barrier = vaultCrypto.barrier = Completer<void>();
      final pending = destinations();
      final checked = expectLater(
        pending,
        _failure(EntryShareCopyError.cancelled),
      );
      await vaultCrypto.entered.future;
      ownerValid = false;
      barrier.complete();
      await checked;
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
    },
  );

  test(
    'real crypto and HTTP create an independently decryptable private copy',
    () async {
      final copy = await prepare();
      expect(copy.entryId, _entry);
      expect(copy.vaultId, _vault);
      expect(copy.owner, _owner);
      expect(copy.toString(), isNot(contains(_value)));
      expect(vaultCrypto.privateCopy, everyElement(0));
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
      expect(vaultCrypto.opened!.vaultDiscoveryKey, everyElement(0));
      expect(privateKey.any((byte) => byte != 0), isTrue);
      await commit(copy);
      expect(copy.isDisposed, isTrue);
      expect(cacheActions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
      expect(requests.map((r) => r.method), ['GET', 'POST', 'POST']);
      expect(requests.any((r) => r.path.contains('entry-shares')), isFalse);
      expect(jsonDecode(requests[1].body), {'count': 1});
      expect(requests.last.body, isNot(contains(_value)));
      final request = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(request['entryId'], _entry);
      expect(request['vaultId'], _vault);
      expect(request['deliveryPolicy'], 'standard');
      expect(request['agentDiscovery'], isNull);
      final plaintext = await entryCrypto.openMemberSecret(
        entryKey: request['entryKey'],
        memberSecret: request['memberSecret'],
        vaultKey: bundle.vaultKey,
      );
      expect((plaintext['content'] as Map)['password'], _value);
      expect(plaintext['discoverable'], isFalse);
      expect(
        (plaintext['agentFieldAccess'] as Map).values,
        everyElement('never'),
      );
      for (final request in requests) {
        expect(request.headers.value('authorization'), 'Bearer ${_jwt()}');
        expect(request.headers.value('cookie'), isNull);
        expect(request.headers.value('x-posthog-session-id'), isNull);
        expect(request.headers.value('cache-control'), 'no-store');
      }
      await expectLater(commit(copy), _failure(EntryShareCopyError.cancelled));
      expect(requests.length, 3);
    },
  );

  test(
    'lost response retries exact ID/ciphertext, not challenge or delivery',
    () async {
      final normal = handler;
      var attempt = 0;
      handler = (request) async {
        if (request.uri.path.endsWith('/entries') && attempt++ == 0) {
          (await request.response.detachSocket(writeHeaders: false)).destroy();
        } else {
          await normal(request);
        }
      };
      final copy = await prepare();
      await expectLater(commit(copy), _failure(EntryShareCopyError.request));
      expect(copy.isDisposed, isFalse);
      expect(cacheActions, [AutoFillMutationAction.invalidate]);
      await commit(copy);
      expect(copy.isDisposed, isTrue);
      expect(
        requests.where((r) => r.path.endsWith('/creation-challenges')).length,
        1,
      );
      final creates = requests
          .where((r) => r.path.endsWith('/entries'))
          .toList();
      expect(creates.length, 2);
      expect(creates.first.body, creates.last.body);
      expect(cacheActions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  final substitutions = <String, void Function(Map<String, dynamic>)>{
    'top Vault': (v) => v['id'] = _entry,
    'top organization': (v) => v['organizationId'] = _entry,
    'wrapper Vault': (v) =>
        v['memberVaultKey']['wrappedVaultKey']['descriptor']['scope']['vaultId'] =
            _entry,
    'wrapper principal': (v) =>
        v['memberVaultKey']['wrappedVaultKey']['descriptor']['scope']['memberId'] =
            _entry,
    'wrapper organization': (v) =>
        v['memberVaultKey']['wrappedVaultKey']['descriptor']['scope']['organizationId'] =
            _entry,
    'wrapper generation': (v) =>
        v['memberVaultKey']['wrappedVaultKey']['descriptor']['memberKeyGeneration'] =
            2,
    'wrapper version': (v) =>
        v['memberVaultKey']['wrappedVaultKey']['descriptor']['wrappedKeyVersion'] =
            2,
    'metadata Vault': (v) =>
        v['memberVaultMetadata']['descriptor']['scope']['vaultId'] = _entry,
    'metadata generation': (v) =>
        v['memberVaultMetadata']['descriptor']['memberKeyGeneration'] = 2,
    'metadata version': (v) =>
        v['memberVaultMetadata']['descriptor']['keyVersion'] = 2,
    'metadata revision': (v) =>
        v['memberVaultMetadata']['descriptor']['resourceRevision'] = '2',
    'discovery Vault': (v) =>
        v['discoveryKey']['descriptor']['scope']['vaultId'] = _entry,
    'discovery version': (v) =>
        v['discoveryKey']['descriptor']['keyVersion'] = 2,
    'discovery generation': (v) =>
        v['discoveryKey']['descriptor']['memberKeyGeneration'] = 2,
    'discovery wrapping epoch': (v) =>
        v['discoveryKey']['descriptor']['binding']['wrappingVaultKeyVersion'] =
            2,
    'unexpected scope': (v) =>
        v['discoveryKey']['descriptor']['scope']['entryId'] = _entry,
  };
  for (final substitution in substitutions.entries) {
    test(
      'independent destination authority rejects ${substitution.key} before crypto',
      () async {
        substitution.value(vaultJson);
        await expectLater(
          prepare(),
          _failure(EntryShareCopyError.invalidAuthority),
        );
        expect(vaultCrypto.privateCopy, isNull);
        expect(requests.length, 1);
      },
    );
  }

  test(
    'cancel while vault crypto is pending wipes borrowed copy and late keys',
    () async {
      final token = CancelToken();
      final barrier = vaultCrypto.barrier = Completer<void>();
      final pending = prepare(token: token);
      final checked = expectLater(
        pending,
        _failure(EntryShareCopyError.cancelled),
      );
      await vaultCrypto.entered.future;
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(vaultCrypto.privateCopy, everyElement(0));
      barrier.complete();
      await checked;
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
      expect(vaultCrypto.opened!.vaultDiscoveryKey, everyElement(0));
      expect(requests.length, 1);
    },
  );

  test('owner loss after crypto rejects material before a challenge', () async {
    final barrier = vaultCrypto.barrier = Completer<void>();
    final pending = prepare();
    final checked = expectLater(
      pending,
      _failure(EntryShareCopyError.cancelled),
    );
    await vaultCrypto.entered.future;
    ownerValid = false;
    barrier.complete();
    await checked;
    expect(vaultCrypto.opened!.vaultKey, everyElement(0));
    expect(requests.length, 1);
  });

  test('owner loss during cache invalidation never sends the create', () async {
    final copy = await prepare();
    notifier.detachHandler();
    notifier.attachHandler((_) async {
      ownerValid = false;
    });
    await expectLater(commit(copy), _failure(EntryShareCopyError.cancelled));
    expect(requests.length, 2);
    copy.dispose();
  });

  test(
    'cache rebuild failure does not turn confirmed save into another create',
    () async {
      final copy = await prepare();
      notifier.detachHandler();
      notifier.attachHandler((action) async {
        if (action == AutoFillMutationAction.rebuild) {
          throw StateError('synthetic rebuild error');
        }
      });
      await commit(copy);
      expect(copy.isDisposed, isTrue);
      await expectLater(commit(copy), _failure(EntryShareCopyError.cancelled));
      expect(requests.length, 3);
    },
  );

  for (final change in [
    {'sub': _entry},
    {'org_id': _entry},
    {'authz_ver': 8},
    {'authz_ver': null},
    {'authz_ver': <String>[]},
  ]) {
    test(
      'transport rejects replaced ${change.keys.single} without POST',
      () async {
        final copy = await prepare();
        when(() => tokens.accessToken).thenAnswer((_) async => _jwt(change));
        await expectLater(
          commit(copy),
          _failure(EntryShareCopyError.cancelled),
        );
        expect(requests.length, 2);
        copy.dispose();
      },
    );
  }

  test(
    'canonical copy sealing wipes a fresh DEK when scope parsing fails',
    () async {
      final observedSodium = _Sodium();
      final random = _Randombytes();
      final dek = Uint8List.fromList(List.filled(32, 123));
      when(() => observedSodium.randombytes).thenReturn(random);
      when(() => random.buf(32)).thenReturn(dek);
      final crypto = EntryV2CryptoService(
        sodiumLoader: () async => observedSodium,
      );
      await expectLater(
        crypto.seal(
          organizationId: _owner.organizationId,
          vaultId: _vault,
          entryId: 'invalid-cryptographic-scope',
          revision: 1,
          vaultKeyVersion: 1,
          vdkVersion: 1,
          memberKeyGeneration: 1,
          operation: 1,
          secret: const EntryShareCopyProjectionService().project(
            snapshot: _snapshot,
          ),
          vaultKey: bundle.vaultKey,
          vaultDiscoveryKey: bundle.vaultDiscoveryKey,
        ),
        throwsA(
          isA<EnvelopeException>().having(
            (error) => error.kind,
            'kind',
            EnvelopeErrorKind.invalidDescriptor,
          ),
        ),
      );
      verify(() => random.buf(32)).called(1);
      expect(dek, everyElement(0));
    },
  );
  test(
    'key change while token storage is pending cannot use the old token',
    () async {
      final copy = await prepare();
      final read = Completer<String?>();
      final entered = Completer<void>();
      when(() => tokens.accessToken).thenAnswer((_) {
        entered.complete();
        return read.future;
      });
      final pending = commit(copy);
      final checked = expectLater(
        pending,
        _failure(EntryShareCopyError.cancelled),
      );
      await entered.future;
      keys.clear();
      read.complete(_jwt());
      await checked;
      expect(requests.length, 2);
      copy.dispose();
    },
  );

  for (final status in [302, 307, 401, 429, 500]) {
    test(
      'copy HTTP $status never redirects, refreshes or retries automatically',
      () async {
        final copy = await prepare();
        handler = (request) async {
          request.response.statusCode = status;
          request.response.headers.set('location', '/unexpected');
          request.response.write('synthetic secret-bearing failure');
          await request.response.close();
        };
        await expectLater(commit(copy), _failure(EntryShareCopyError.request));
        expect(requests.length, 3);
        verifyNever(() => tokens.refreshToken);
        copy.dispose();
      },
    );
  }

  EntryShareCopyCubit createCubit({
    EntryShareLifetime? lifetime,
    Future<EntrySharingSession?> Function()? ownerReader,
    Uint8List Function()? keyReader,
  }) {
    final cubit = EntryShareCopyCubit(
      service: service,
      snapshot: _snapshot,
      owner: _owner,
      ownerReader: ownerReader ?? () async => ownerValid ? _owner : null,
      copyMemberPrivateKey: keyReader ?? () => Uint8List.fromList(privateKey),
      lifetime: lifetime ?? EntryShareLifetime(),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test(
    'copy Cubit is idle until explicit save and rejects duplicate taps',
    () async {
      final cubit = createCubit();
      final states = <EntryShareCopyState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      expect(requests, isEmpty);
      final first = cubit.save(vaultId: _vault);
      await cubit.save(vaultId: _entry);
      await first;
      expect(cubit.state.phase, EntryShareCopyPhase.saved);
      expect(cubit.state.entryId, _entry);
      expect(cubit.state.vaultId, _vault);
      expect(requests.length, 3);
      await cubit.save(vaultId: _vault);
      await cubit.retry();
      expect(requests.length, 3);
      expect(
        states.map((state) => state.toString()).join(),
        isNot(contains(_value)),
      );
    },
  );

  test(
    'copy Cubit retains only the original encrypted retry after lost response',
    () async {
      final normal = handler;
      var attempts = 0;
      handler = (request) async {
        if (request.uri.path.endsWith('/entries') && attempts++ == 0) {
          (await request.response.detachSocket(writeHeaders: false)).destroy();
        } else {
          await normal(request);
        }
      };
      final keyCopy = Uint8List.fromList(privateKey);
      final cubit = createCubit(keyReader: () => keyCopy);
      await cubit.save(vaultId: _vault);
      expect(cubit.state.phase, EntryShareCopyPhase.retry);
      expect(keyCopy, everyElement(0));
      await cubit.save(
        vaultId: _entry,
        title: 'Cannot replace an ambiguous create',
      );
      expect(requests.length, 3);
      final retry = cubit.retry();
      await cubit.retry();
      await retry;
      expect(cubit.state.phase, EntryShareCopyPhase.saved);
      expect(requests.length, 4);
      expect(requests[2].body, requests[3].body);
    },
  );

  test(
    'copy Cubit allows correction of input before any destination request',
    () async {
      final cubit = createCubit();
      await cubit.save(vaultId: _vault, title: ' ');
      expect(cubit.state.phase, EntryShareCopyPhase.editing);
      expect(cubit.state.inputError, EntryShareCopyInputError.invalidTitle);
      expect(requests, isEmpty);
      await cubit.save(vaultId: _vault, title: 'Explicit replacement title');
      expect(cubit.state.phase, EntryShareCopyPhase.saved);
    },
  );

  test(
    'copy Cubit clear wipes keys immediately and rejects late crypto',
    () async {
      final barrier = vaultCrypto.barrier = Completer<void>();
      final keyCopy = Uint8List.fromList(privateKey);
      final cubit = createCubit(keyReader: () => keyCopy);
      final save = cubit.save(vaultId: _vault);
      await vaultCrypto.entered.future;
      cubit.clear();
      expect(keyCopy, everyElement(0));
      await Future<void>.delayed(Duration.zero);
      expect(vaultCrypto.privateCopy, everyElement(0));
      barrier.complete();
      await save;
      expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
      expect(vaultCrypto.opened!.vaultKey, everyElement(0));
      expect(vaultCrypto.opened!.vaultDiscoveryKey, everyElement(0));
      expect(requests.length, 1);
      await cubit.save(vaultId: _vault);
      await cubit.retry();
      expect(requests.length, 1);
    },
  );

  test(
    'copy Cubit changing owner during crypto prevents challenge and save',
    () async {
      final barrier = vaultCrypto.barrier = Completer<void>();
      final cubit = createCubit();
      final save = cubit.save(vaultId: _vault);
      await vaultCrypto.entered.future;
      ownerValid = false;
      barrier.complete();
      await save;
      expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
      expect(requests.length, 1);
    },
  );

  test('copy Cubit does not renew the original receive deadline', () async {
    var elapsed = const Duration(minutes: 14);
    final lifetime = EntryShareLifetime(age: elapsed, elapsed: () => elapsed);
    final barrier = vaultCrypto.barrier = Completer<void>();
    final cubit = createCubit(lifetime: lifetime);
    final save = cubit.save(vaultId: _vault);
    await vaultCrypto.entered.future;
    elapsed += const Duration(minutes: 1);
    barrier.complete();
    await save;
    expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
    expect(requests.length, 1);
  });

  test(
    'copy Cubit rejects expired reception before copying private key',
    () async {
      var copies = 0;
      final cubit = createCubit(
        lifetime: EntryShareLifetime(age: EntryShareLifetime.maximum),
        keyReader: () {
          copies++;
          return Uint8List.fromList(privateKey);
        },
      );
      await cubit.save(vaultId: _vault);
      expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
      expect(requests, isEmpty);
      expect(copies, 0);
    },
  );

  test(
    'copy Cubit owner lookup failure retires plaintext without requests',
    () async {
      final cubit = createCubit(
        ownerReader: () async => throw StateError(_value),
      );
      await cubit.save(vaultId: _vault);
      expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
      expect(requests, isEmpty);
    },
  );

  test(
    'copy Cubit does not resurrect after clear during pending owner lookup',
    () async {
      final read = Completer<EntrySharingSession?>();
      var copies = 0;
      final cubit = createCubit(
        ownerReader: () => read.future,
        keyReader: () {
          copies++;
          return Uint8List.fromList(privateKey);
        },
      );
      final save = cubit.save(vaultId: _vault);
      cubit.clear();
      read.complete(_owner);
      await save;
      expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
      expect(copies, 0);
      expect(requests, isEmpty);
    },
  );

  test('copy Cubit expiry prevents retry of an ambiguous save', () async {
    var elapsed = Duration.zero;
    final normal = handler;
    handler = (request) async {
      if (request.uri.path.endsWith('/entries')) {
        (await request.response.detachSocket(writeHeaders: false)).destroy();
      } else {
        await normal(request);
      }
    };
    final cubit = createCubit(
      lifetime: EntryShareLifetime(elapsed: () => elapsed),
    );
    await cubit.save(vaultId: _vault);
    expect(cubit.state.phase, EntryShareCopyPhase.retry);
    elapsed = EntryShareLifetime.maximum;
    await cubit.retry();
    expect(cubit.state.phase, EntryShareCopyPhase.unavailable);
    expect(requests.length, 3);
  });
}
