// Isolated debug workload: synthetic data, loopback HTTP, no account services.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_palladin/core/crypto/asymmetric_keys.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/vault/data/datasources/member_sync_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_index_preparation_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_cache.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/member_vault_key_context_store.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:mobile_palladin/features/autofill/data/autofill_incremental_publisher.dart';
import 'package:mobile_palladin/features/autofill/data/durable_autofill_repair_coordinator.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_incremental.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';

const _organization = '11111111-1111-4111-8111-111111111111';
const _principal = '44444444-4444-4444-8444-444444444444';
const _vaultCount = 8;
const _entriesPerVault = 20;
String _id(int n) => '22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}';
String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Debug benchmark only');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    await runBenchmark(incremental: true);
    debugPrint('MEMBER_BENCHMARK_DONE');
  } catch (error) {
    // Never print exception payloads that could retain decrypted test data.
    debugPrint('MEMBER_BENCHMARK_FAILED ${error.runtimeType}');
    rethrow;
  }
}

Future<List<Map<String, Object>>> runBenchmark({
  int repetitions = 5,
  bool incremental = false,
}) async {
  debugPrint(
    'MEMBER_BENCHMARK_ENV ${jsonEncode({'revision': const String.fromEnvironment('BENCHMARK_REVISION', defaultValue: 'unspecified'), 'os': Platform.operatingSystem, 'osVersion': Platform.operatingSystemVersion, 'dart': Platform.version, 'buildMode': kDebugMode ? 'debug' : 'other', 'vaults': _vaultCount, 'entriesPerVault': _entriesPerVault, 'injectedDelay': false})}',
  );
  final sodium = await SodiumProvider.instance();
  final pair = sodium.crypto.box.keyPair();
  final privateKey = pair.secretKey.extractBytes();
  final fingerprint = vaultPublicKeyFingerprint(
    VaultPublicKeyKind.memberX25519,
    pair.publicKey,
  );
  final crypto = EntryV2CryptoService();
  final vaultKeys = VaultRotationCryptoService();
  final contexts = <String, Map<String, dynamic>>{};
  final wrappers = <String, Map<String, dynamic>>{};
  final heads = <String, List<Map<String, Object?>>>{};
  Map<String, Object?>? updatedHead;
  var deltaSequence = 1;
  List<Map<String, Object?>> deltaItems = [];
  final issued = DateTime.now().toUtc();
  HttpServer? server;
  final directory = await Directory.systemTemp.createTemp(
    'palladin-benchmark-',
  );
  final database = await openDatabase(
    '${directory.path}/member.db',
    version: 2,
    onConfigure: configureMemberSyncDatabase,
    onCreate: (db, _) async {
      // Isolated schema fixture; never open or clear the application cache.
      await db.execute(
        'CREATE TABLE member_sync_heads (vault_id TEXT NOT NULL, generation TEXT NOT NULL, entry_id TEXT NOT NULL, envelope_json TEXT NOT NULL, PRIMARY KEY (vault_id, generation, entry_id))',
      );
      await db.execute(
        'CREATE TABLE member_sync_state (vault_id TEXT PRIMARY KEY, applied_sequence TEXT NOT NULL, access_context_json TEXT NOT NULL, member_vault_key_json TEXT NOT NULL, maximum_observed_wall_micros INTEGER NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE member_sync_profile_fence (singleton INTEGER PRIMARY KEY CHECK (singleton = 1), generation INTEGER NOT NULL)',
      );
    },
  );
  final cache = SqliteMemberSyncCache(databaseLoader: () async => database);
  final results = <Map<String, Object>>[];
  try {
    for (var v = 0; v < _vaultCount; v++) {
      final vaultId = _id(v + 1);
      final vaultKey = sodium.randombytes.buf(32);
      final wrapperContext = WrapperContext(
        purpose: WrapperPurpose.memberVaultKey,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(_organization),
          vaultId: EnvelopeId.parse(vaultId),
          memberId: EnvelopeId.parse(_principal),
        ),
        resourceRevision: 1,
        wrappedKeyVersion: 1,
        memberKeyGeneration: 1,
        recipientKeyKind: 5,
        recipientKeyVersion: 1,
        recipientFingerprint: fingerprint,
      );
      try {
        final sealed = await X25519SealedBoxKeyWrapper().seal(
          key: vaultKey,
          context: wrapperContext,
          recipient: X25519PublicKey(pair.publicKey),
        );
        wrappers[vaultId] = {
          'wrappedVaultKey': {
            'descriptor': {
              'protocolVersion': 2,
              'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
              'purpose': 1,
              'scope': {
                'organizationId': _organization,
                'vaultId': vaultId,
                'entryId': null,
                'grantOrRequestId': null,
                'agentId': null,
                'memberId': _principal,
              },
              'resourceRevision': '1',
              'wrappedKeyVersion': 1,
              'memberKeyGeneration': 1,
              'recipientKeyKind': 5,
              'recipientKeyVersion': 1,
              'recipientFingerprint': _b64(fingerprint),
              'parentDescriptorHash': null,
            },
            'encodedSealedKeyPackage': _b64(sealed),
          },
        };
        contexts[vaultId] = {
          'contextVersion': 1,
          'principalId': _principal,
          'organizationId': _organization,
          'organizationMembershipGeneration': '1',
          'vaultId': vaultId,
          'memberId': _principal,
          'memberKeyGeneration': 1,
          'vaultKeyVersion': 1,
          'memberRecipientKeyVersion': 1,
          'memberRecipientKeyFingerprint': _b64(fingerprint),
          'offlinePolicy': '24h',
          'offlinePolicyVersion': 1,
          'issuedAt': issued.toIso8601String(),
          'notAfter': issued.add(const Duration(hours: 24)).toIso8601String(),
        };
        heads[vaultId] = [];
        for (var e = 0; e < _entriesPerVault; e++) {
          final entryId = _id(1000 + v * _entriesPerVault + e);
          for (final revision in v == 0 && e == 0 ? [1, 2] : [1]) {
            final bundle = await crypto.seal(
              organizationId: _organization,
              vaultId: vaultId,
              entryId: entryId,
              revision: revision,
              vaultKeyVersion: 1,
              vdkVersion: 1,
              memberKeyGeneration: 1,
              operation: 1,
              secret: MemberSecret(
                entryType: VaultEntryType.credential,
                memberLabel: 'Synthetic $e',
                agentLabel: null,
                description: null,
                icon: null,
                color: null,
                discoverable: false,
                content: const CredentialSecretContent(
                  username: 'synthetic',
                  password: 'synthetic-only',
                  url: 'https://example.invalid',
                  urlDomain: 'example.invalid',
                  totp: null,
                  notes: null,
                  customFields: [],
                ),
                agentFieldAccess: {
                  for (final field in [
                    'memberLabel',
                    'agentLabel',
                    'description',
                    'icon',
                    'color',
                    'entryType',
                    'credential.username',
                    'credential.password',
                    'credential.url',
                    'credential.urlDomain',
                    'credential.totp',
                    'notes',
                  ])
                    field: AgentFieldAccess.never,
                },
              ),
              vaultKey: vaultKey,
              vaultDiscoveryKey: vaultKey,
            );
            final head = <String, Object?>{
              'entryId': entryId,
              'kind': 'head',
              'state': 'active',
              'currentRevision': '$revision',
              'memberIndexRevision': '$revision',
              'currentKeyVersion': 1,
              'updatedAt': issued.toIso8601String(),
              'entryKey': bundle.entryKey,
              'memberIndex': bundle.memberIndex,
              'memberSecret': bundle.memberSecret,
            };
            if (revision == 1) {
              heads[vaultId]!.add(head);
            } else {
              updatedHead = head;
            }
          }
        }
      } finally {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
    final requests = <String, int>{};
    var activeRequests = 0;
    var peakRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      activeRequests++;
      if (activeRequests > peakRequests) peakRequests = activeRequests;
      final segments = request.uri.pathSegments;
      final kind = segments.length == 2 ? 'list' : segments.last;
      requests[kind] = (requests[kind] ?? 0) + 1;
      await request.drain<void>();
      Object body;
      if (kind == 'list') {
        body = [
          for (final id in wrappers.keys)
            {'id': id, 'memberVaultKey': wrappers[id]},
        ];
      } else {
        final id = segments[2];
        if (!heads.containsKey(id) || !{'snapshot', 'delta'}.contains(kind)) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        body = {
          'accessContext': contexts[id],
          'memberVaultKey': wrappers[id],
          'items': kind == 'snapshot'
              ? heads[id]
              : (id == _id(1) ? deltaItems : []),
          if (kind == 'snapshot') 'snapshotBaseSequence': '1',
          if (kind == 'snapshot') 'nextCursor': null,
          if (kind == 'delta')
            'deltaUpperBound': '${id == _id(1) ? deltaSequence : 1}',
          if (kind == 'delta')
            'appliedThroughSequence': '${id == _id(1) ? deltaSequence : 1}',
          if (kind == 'delta') 'continuationCursor': null,
        };
      }
      final bytes = utf8.encode(jsonEncode(body));
      request.response.headers
        ..contentType = ContentType.json
        ..set('X-Palladin-Vault-Protocol', '2')
        ..set('X-Palladin-Sync-Policy', '2')
        ..set('Content-Encoding', 'identity')
        ..contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
      activeRequests--;
    });
    for (var repetition = 0; repetition < repetitions + 1; repetition++) {
      // Alternate order; repetition zero warms up FFI, transport and SQLite.
      final modes = repetition.isEven
          ? ['sequential', 'batch4']
          : ['batch4', 'sequential'];
      for (final mode in modes) {
        await cache.clearAll();
        requests.clear();
        peakRequests = 0;
        final dio = Dio(
          BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'),
        );
        final keyContexts = MemberVaultKeyContextStore();
        final loader = _VaultList(dio, keyContexts);
        final sync = MemberSyncService(
          remote: MemberSyncRemoteDatasource(dio),
          cache: cache,
          entryCrypto: crypto,
          vaultKeys: vaultKeys,
        );
        final entries = MemberEntryListService(
          vaults: VaultRemoteDatasource(dio),
          keys: vaultKeys,
          sync: sync,
          authorityProvider: _Authority(),
          keyContexts: keyContexts,
        );
        try {
          final watch = Stopwatch()..start();
          if (mode == 'batch4') {
            await MemberIndexPreparationService(
              vaults: loader,
              entries: entries,
            ).prepare(privateKey);
          } else {
            final vaults = await loader.loadForMemberIndex(privateKey);
            for (final vault in vaults) {
              await entries.load(
                vaultId: vault.id,
                memberPrivateKey: privateKey,
              );
            }
          }
          watch.stop();
          final count = wrappers.keys.fold<int>(
            0,
            (n, id) => n + sync.entries(id).length,
          );
          final invalidIndexes = wrappers.keys.any(
            (id) => sync
                .entries(id)
                .any(
                  (entry) =>
                      entry.corrupt ||
                      !entry.memberLabel.startsWith('Synthetic '),
                ),
          );
          if (invalidIndexes ||
              count != _vaultCount * _entriesPerVault ||
              requests['list'] != 1 ||
              requests['snapshot'] != _vaultCount ||
              requests['delta'] != _vaultCount ||
              requests.values.fold<int>(0, (a, b) => a + b) != 17) {
            throw StateError('Benchmark request/result invariant failed');
          }
          final result = <String, Object>{
            'mode': mode,
            'warmup': repetition == 0,
            'iteration': repetition,
            'elapsedMicros': watch.elapsedMicroseconds,
            'entries': count,
            'peakHttpRequests': peakRequests,
            'requests': Map<String, int>.from(requests),
          };
          results.add(result);
          debugPrint('MEMBER_BENCHMARK ${jsonEncode(result)}');
          if (incremental && repetition == repetitions && mode == modes.last) {
            final preparationAuthority = _Authority();
            final reader = _CountingCurrentEntries(
              reader: sync,
              authorityProvider: preparationAuthority,
              vaultKeys: vaultKeys,
              entryCrypto: crypto,
              canonicalAdapter: CanonicalEntryDetailService(
                entries: EntryRemoteDatasource(dio),
                vaults: VaultRemoteDatasource(dio),
                keys: vaultKeys,
                envelopes: VaultProtocolEnvelopeService(),
                grants: GrantsRemoteDatasource(dio),
                entryV2: crypto,
                autoFillMutationNotifier: AutoFillMutationNotifier(),
              ),
            );
            final bridge = _BenchmarkPublicationSink();
            final publisher = AutoFillIncrementalPublisher(
              bridge: bridge,
              metadata: sync,
              authority: preparationAuthority,
              entries: reader,
            );
            await publisher.beginSession(1);
            Future<void> publish(
              String phase,
              int expectedReveals,
              int expectedUpserts,
              int expectedRemovals,
            ) async {
              final beforeRequests = requests.values.fold<int>(
                0,
                (a, b) => a + b,
              );
              reader.reveals = 0;
              preparationAuthority.reads = 0;
              final timer = Stopwatch()..start();
              await publisher.synchronize(
                privateKey: privateKey,
                vaultIds: wrappers.keys,
                isCurrent: () => true,
                onProgress: (_) {},
              );
              timer.stop();
              final afterRequests = requests.values.fold<int>(
                0,
                (a, b) => a + b,
              );
              if (reader.reveals != expectedReveals ||
                  bridge.upserts != expectedUpserts ||
                  bridge.removals != expectedRemovals ||
                  beforeRequests != afterRequests) {
                throw StateError('Incremental preparation invariant failed');
              }
              final measurement = <String, Object>{
                'mode': 'incremental-$phase',
                'authorityReads': preparationAuthority.reads,
                'elapsedMicros': timer.elapsedMicroseconds,
                'reveals': reader.reveals,
                'upserts': bridge.upserts,
                'removals': bridge.removals,
                'httpRequests': afterRequests - beforeRequests,
              };
              results.add(measurement);
              debugPrint('MEMBER_BENCHMARK ${jsonEncode(measurement)}');
            }

            try {
              await publish('full', 160, 160, 0);
              int requestCount() =>
                  requests.values.fold<int>(0, (a, b) => a + b);
              final prepared = _BenchmarkPreparedPublisher(
                publisher,
                requestCount,
              );
              final identity = Object();
              final failures = <Object>[];
              final coordinator = DurableAutoFillRepairCoordinator(
                memberIndexes: sync,
                autoFill: prepared,
                currentSession: () => AutoFillRepairSession(
                  principalId: _principal,
                  identity: identity,
                  privateKey: privateKey,
                ),
                onFailure: failures.add,
              );
              coordinator.start();
              coordinator.replaceKnownVaults(wrappers.keys);
              try {
                final beforeRequests = requestCount();
                final beforeRevision = bridge.revision;
                final beforeWrites = bridge.nativeWrites;
                final beforeDenies = bridge.denies;
                final beforeValidation = bridge.validationCalls;
                reader.reveals = 0;
                preparationAuthority.reads = 0;
                final context = contexts[_id(1)]!;
                context['issuedAt'] = issued
                    .add(const Duration(seconds: 1))
                    .toIso8601String();
                context['notAfter'] = issued
                    .add(const Duration(hours: 24, seconds: 1))
                    .toIso8601String();
                final renewalTimer = Stopwatch()..start();
                await entries.load(
                  vaultId: _id(1),
                  memberPrivateKey: privateKey,
                );
                await coordinator.drainPending();
                renewalTimer.stop();
                final measurement = <String, Object>{
                  'mode': 'incremental-renewal',
                  'elapsedMicros': renewalTimer.elapsedMicroseconds,
                  'syncHttpRequests': requestCount() - beforeRequests,
                  'httpRequests': prepared.httpRequests,
                  'reveals': reader.reveals,
                  'denies': bridge.denies - beforeDenies,
                  'nativeValidationCalls':
                      bridge.validationCalls - beforeValidation,
                  'nativeWrites': bridge.nativeWrites - beforeWrites,
                  'sameBase': bridge.revision == beforeRevision,
                };
                if (failures.isNotEmpty ||
                    prepared.calls != 1 ||
                    measurement['syncHttpRequests'] != 1 ||
                    prepared.httpRequests != 0 ||
                    reader.reveals != 0 ||
                    measurement['denies'] != 0 ||
                    measurement['nativeValidationCalls'] != 1 ||
                    measurement['nativeWrites'] != 0 ||
                    measurement['sameBase'] != true) {
                  throw StateError(
                    'Real durable renewal must preserve acknowledged native publication: ${jsonEncode(measurement)}',
                  );
                }
                results.add(measurement);
                debugPrint('MEMBER_BENCHMARK ${jsonEncode(measurement)}');
              } finally {
                await coordinator.dispose();
              }

              final coordinate = AutoFillEntryCoordinate(
                vaultId: _id(1),
                entryId: _id(1000),
              );
              await publisher.deny({coordinate});
              deltaItems = [updatedHead!];
              deltaSequence = 2;
              final beforeUpdate = requests.values.fold<int>(
                0,
                (a, b) => a + b,
              );
              await entries.load(vaultId: _id(1), memberPrivateKey: privateKey);
              if (requests.values.fold<int>(0, (a, b) => a + b) !=
                  beforeUpdate + 1) {
                throw StateError('Update must fetch only one delta');
              }
              await publish('update', 1, 1, 0);
              await publisher.deny({coordinate});
              deltaItems = [
                {
                  for (final field in updatedHead.keys) field: null,
                  'entryId': _id(1000),
                  'kind': 'tombstone',
                },
              ];
              deltaSequence = 3;
              final beforeDelete = requests.values.fold<int>(
                0,
                (a, b) => a + b,
              );
              await entries.load(vaultId: _id(1), memberPrivateKey: privateKey);
              if (requests.values.fold<int>(0, (a, b) => a + b) !=
                  beforeDelete + 1) {
                throw StateError('Delete must fetch only one delta');
              }
              await publish('delete', 0, 0, 1);
            } finally {
              await publisher.endSession();
            }
          }
        } finally {
          entries.lock();
          dio.close(force: true);
        }
      }
    }
    return results;
  } finally {
    await server?.close(force: true);
    await database.close();
    await directory.delete(recursive: true);
    privateKey.fillRange(0, privateKey.length, 0);
    pair.secretKey.dispose();
    fingerprint.fillRange(0, fingerprint.length, 0);
  }
}

// Fixture substitutes account authentication only; production authority checks
// still validate each server context against these independent fixed claims.
class _Authority extends MemberSyncSessionAuthorityProvider {
  _Authority() : super(SecureTokenStorage(const FlutterSecureStorage()));
  int reads = 0;
  @override
  Future<MemberSyncSessionAuthority> current() async {
    reads++;
    return const MemberSyncSessionAuthority(
      principalId: _principal,
      organizationId: _organization,
      organizationMembershipGeneration: '1',
      offlinePolicy: '24h',
      offlinePolicyVersion: 1,
    );
  }
}

class _VaultList implements MemberVaultListLoader {
  _VaultList(this.dio, this.contexts);
  final Dio dio;
  final MemberVaultKeyContextStore contexts;
  @override
  Future<List<VaultEntity>> loadForMemberIndex(
    Uint8List memberPrivateKey, {
    bool ensureFresh = false,
  }) async {
    final response = await dio.get<List<dynamic>>('/api/vaults');
    return [
      for (final raw in response.data!)
        _vault(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  VaultEntity _vault(Map<String, dynamic> raw) {
    final id = raw['id'] as String;
    contexts.install(
      vaultId: id,
      memberVaultKey: Map<String, dynamic>.from(raw['memberVaultKey'] as Map),
      memberKeyGeneration: 1,
    );
    return VaultEntity(
      id: id,
      name: 'Synthetic',
      grantMode: GrantMode.granular,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      entryCount: _entriesPerVault,
      activeGrantCount: 0,
      memberCount: 1,
    );
  }
}

// Counts actual production reveals; every invocation still performs real SQLite,
// wrapper opening, MemberSecret AEAD and final read-authority revalidation.
class _CountingCurrentEntries extends LocalCurrentEntryService {
  _CountingCurrentEntries({
    required super.reader,
    required super.authorityProvider,
    required super.vaultKeys,
    required super.entryCrypto,
    required super.canonicalAdapter,
  });
  int reveals = 0;
  @override
  Future<LocalCurrentEntryReveal> revealPreparedWithAuthority({
    required MemberPreparationAuthority authority,
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
  }) {
    reveals++;
    return super.revealPreparedWithAuthority(
      authority: authority,
      vaultId: vaultId,
      entryId: entryId,
      memberPrivateKey: memberPrivateKey,
    );
  }
}

// Desktop benchmark stops at native publication. It retains counts only, never
// credential bodies; native ciphertext/CAS/biometric behavior has separate tests.
class _BenchmarkPreparedPublisher implements AutoFillPreparedCacheSynchronizer {
  _BenchmarkPreparedPublisher(this.publisher, this.requestCount);
  final AutoFillIncrementalPublisher publisher;
  final int Function() requestCount;
  int calls = 0;
  int httpRequests = 0;

  @override
  Future<void> synchronizePrepared({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
  }) async {
    calls++;
    final before = requestCount();
    await publisher.synchronize(
      privateKey: privateKey,
      vaultIds: vaultIds,
      isCurrent: () => true,
      onProgress: (_) {},
    );
    httpRequests += requestCount() - before;
  }
}

class _BenchmarkPublicationSink implements AutoFillIncrementalCacheBridge {
  int revision = 0;
  int upserts = 0;
  int removals = 0;
  int nativeWrites = 0;
  int denies = 0;
  int validationCalls = 0;
  AutoFillCacheManifest? _manifest;
  final _owners = <String>{};
  AutoFillCacheBase next() {
    nativeWrites++;
    return AutoFillCacheBase(generation: 1, revision: ++revision);
  }

  @override
  Future<int> beginWriterSession({required int sessionToken}) async => 1;
  @override
  Future<void> endWriterSession({required int writerEpoch}) async {}
  @override
  Future<AutoFillCacheBase> replaceCacheV3(
    AutoFillCachePayload payload, {
    required int sessionToken,
    required int writerEpoch,
    required void Function() validatePublication,
    AutoFillCacheBase? base,
    List<String> releasingDenies = const [],
  }) async {
    validatePublication();
    upserts = payload.records.length;
    removals = 0;
    _manifest = payload.manifest;
    _owners.removeAll(releasingDenies);
    return next();
  }

  @override
  Future<AutoFillScopedDenial> denyEntries({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required List<AutoFillEntryCoordinate> entries,
  }) async {
    if (base.revision != revision) throw StateError('Stale synthetic base');
    denies++;
    final nextBase = next();
    final token = 'synthetic-$revision';
    _owners.add(token);
    return AutoFillScopedDenial(base: nextBase, token: token);
  }

  @override
  Future<AutoFillCacheBase> applyCacheDelta({
    required AutoFillCacheBase base,
    required int writerEpoch,
    required AutoFillCacheManifest manifest,
    required List<AutoFillRecord> upserts,
    required List<AutoFillEntryCoordinate> removals,
    required List<String> releasingDenies,
    required void Function() validatePublication,
  }) async {
    validatePublication();
    validationCalls++;
    if (base.revision != revision) throw StateError('Stale synthetic base');
    this.upserts = upserts.length;
    this.removals = removals.length;
    if (upserts.isEmpty &&
        removals.isEmpty &&
        releasingDenies.isEmpty &&
        _owners.isEmpty &&
        _sameAuthority(manifest)) {
      return base;
    }
    if (!_owners.containsAll(releasingDenies)) {
      throw StateError('Unknown synthetic owner');
    }
    _owners.removeAll(releasingDenies);
    _manifest = manifest;
    return next();
  }

  bool _sameAuthority(AutoFillCacheManifest candidate) {
    final previous = _manifest;
    if (previous == null) return false;
    Map<String, Object> bindings(AutoFillCacheManifest manifest) {
      final value = manifest.toPlatformMap();
      value['vaults'] = (value['vaults'] as List)
          .map(
            (raw) => {
              for (final field in (raw as Map).entries)
                if (field.key != 'issuedAt' && field.key != 'notAfter')
                  field.key: field.value,
            },
          )
          .toList();
      return value;
    }

    final now = DateTime.now().toUtc();
    return jsonEncode(bindings(previous)) == jsonEncode(bindings(candidate)) &&
        previous.vaults.entries.every((entry) {
          final next = candidate.vaults[entry.key];
          return next != null &&
              now.isBefore(entry.value.notAfter) &&
              now.isBefore(next.notAfter) &&
              !next.notAfter.isBefore(entry.value.notAfter) &&
              next.issuedAt.isBefore(entry.value.notAfter) &&
              entry.value.issuedAt.isBefore(next.notAfter);
        });
  }
}
