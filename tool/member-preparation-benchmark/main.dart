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

import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_credential_source.dart';
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
    await runBenchmark();
    debugPrint('MEMBER_BENCHMARK_DONE');
  } catch (error) {
    // Never print exception payloads that could retain decrypted test data.
    debugPrint('MEMBER_BENCHMARK_FAILED ${error.runtimeType}');
    rethrow;
  }
}

Future<List<Map<String, Object>>> runBenchmark({int repetitions = 5}) async {
  debugPrint(
    'MEMBER_BENCHMARK_ENV ${jsonEncode({
      'revision': const String.fromEnvironment('BENCHMARK_REVISION', defaultValue: 'unspecified'),
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'buildMode': kDebugMode ? 'debug' : 'other',
      'vaults': _vaultCount,
      'entriesPerVault': _entriesPerVault,
      'warmRepeatRequestDelaysMillis': [0, 25],
    })}',
  );
  final sodium = await SodiumProvider.instance();
  final pair = sodium.crypto.box.keyPair();
  final privateKey = pair.secretKey.extractBytes();
  final fingerprint = vaultPublicKeyFingerprint(
    VaultPublicKeyKind.memberX25519,
    pair.publicKey,
  );
  final crypto = _CountingEntryCrypto();
  final vaultKeys = _CountingVaultKeys();
  final contexts = <String, Map<String, dynamic>>{};
  final wrappers = <String, Map<String, dynamic>>{};
  final heads = <String, List<Map<String, Object?>>>{};
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
          final bundle = await crypto.seal(
            organizationId: _organization,
            vaultId: vaultId,
            entryId: entryId,
            revision: 1,
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
            'currentRevision': '1',
            'memberIndexRevision': '1',
            'currentKeyVersion': 1,
            'updatedAt': issued.toIso8601String(),
            'entryKey': bundle.entryKey,
            'memberIndex': bundle.memberIndex,
            'memberSecret': bundle.memberSecret,
          };
          heads[vaultId]!.add(head);
        }
      } finally {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
    final requests = <String, int>{};
    var requestDelay = Duration.zero;
    var activeRequests = 0;
    var peakRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final loopbackServer = server;
    server.listen((request) async {
      activeRequests++;
      if (activeRequests > peakRequests) peakRequests = activeRequests;
      final segments = request.uri.pathSegments;
      final kind = segments.length == 2 ? 'list' : segments.last;
      requests[kind] = (requests[kind] ?? 0) + 1;
      await request.drain<void>();
      if (requestDelay != Duration.zero) {
        await Future<void>.delayed(requestDelay);
      }
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
          'items': kind == 'snapshot' ? heads[id] : [],
          if (kind == 'snapshot') 'snapshotBaseSequence': '1',
          if (kind == 'snapshot') 'nextCursor': null,
          if (kind == 'delta') 'deltaUpperBound': '1',
          if (kind == 'delta') 'appliedThroughSequence': '1',
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
          BaseOptions(baseUrl: 'http://127.0.0.1:${loopbackServer.port}'),
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
          if (repetition == repetitions && mode == modes.last) {
            // Baseline repeat of the real preparer after completion, not a
            // native provider activation benchmark. Keep the same live indexes.
            final preparer = MemberIndexPreparationService(
              vaults: loader,
              entries: entries,
            );
            for (final delayMillis in [0, 25]) {
              requestDelay = Duration(milliseconds: delayMillis);
              requests.clear();
              crypto.indexReads = 0;
              crypto.secretReads = 0;
              vaultKeys.opens = 0;
              final repeatTimer = Stopwatch()..start();
              await preparer.prepare(privateKey);
              repeatTimer.stop();
              final repeat = <String, Object>{
                'mode': delayMillis == 0 ? 'warm-repeat' : 'warm-repeat-slow',
                'entries': wrappers.keys.fold<int>(
                  0,
                  (count, id) => count + sync.entries(id).length,
                ),
                'requests': Map<String, int>.from(requests),
                'vaultKeyOpens': vaultKeys.opens,
                'indexOpens': crypto.indexReads,
                'secretOpens': crypto.secretReads,
                'requestDelayMillis': delayMillis,
                'elapsedMicros': repeatTimer.elapsedMicroseconds,
              };
              results.add(repeat);
              debugPrint('MEMBER_BENCHMARK ${jsonEncode(repeat)}');
            }
            // Actual transport is unavailable; candidates and selected reads
            // must use the original finite lease and canonical local source.
            await loopbackServer.close(force: true);
            server = null;

            final reader = _CountingCurrentEntries(
              reader: sync,
              authorityProvider: _Authority(),
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
            final source = AutoFillCredentialSource(
              memberIndex: sync,
              localEntries: reader,
            );
            final beforeRequests = requests.values.fold<int>(
              0,
              (a, b) => a + b,
            );
            crypto.secretReads = 0;
            crypto.indexReads = 0;
            vaultKeys.opens = 0;
            final timer = Stopwatch()..start();
            final candidates = await source.candidates(
              vaultIds: wrappers.keys,
              verifiedHosts: {'example.invalid'},
              validateRequest: () {},
            );
            final candidateSecretReads = crypto.secretReads;
            final candidateIndexOpens = crypto.indexReads;
            final candidateVaultKeyOpens = vaultKeys.opens;
            final candidateMicros = timer.elapsedMicroseconds;
            final selected = candidates.last;
            var credentialVerified = false;
            timer.reset();
            await source.withCredential(
              candidate: selected,
              selectedHost: 'example.invalid',
              memberPrivateKey: privateKey,
              validateRequest: () {},
              complete: (credential) async {
                credentialVerified =
                    credential.username == 'synthetic' &&
                    credential.password == 'synthetic-only';
              },
            );
            timer.stop();
            final httpRequests =
                requests.values.fold<int>(0, (a, b) => a + b) - beforeRequests;
            final onlySelectedEntryRead =
                reader.reads.length == 1 &&
                reader.reads.single == (selected.vaultId, selected.entryId);
            final selectedSecretReads =
                crypto.secretReads - candidateSecretReads;
            if (candidates.length != 160 ||
                candidateSecretReads != 0 ||
                selectedSecretReads != 1 ||
                !onlySelectedEntryRead ||
                !credentialVerified ||
                httpRequests != 0) {
              throw StateError('Shared source selected-only invariant failed');
            }
            final measurement = <String, Object>{
              'mode': 'shared-source',
              'networkOffline': true,
              'candidateIndexOpens': candidateIndexOpens,
              'candidateVaultKeyOpens': candidateVaultKeyOpens,
              'candidates': candidates.length,
              'candidateSecretReads': candidateSecretReads,
              'selectedSecretReads': selectedSecretReads,
              'selectedEntryReads': reader.reads.length,
              'onlySelectedEntryRead': onlySelectedEntryRead,
              'credentialVerified': credentialVerified,
              'httpRequests': httpRequests,
              'candidateElapsedMicros': candidateMicros,
              'selectedElapsedMicros': timer.elapsedMicroseconds,
            };
            results.add(measurement);
            debugPrint('MEMBER_BENCHMARK ${jsonEncode(measurement)}');
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

// Counts the actual production body opener; no body values leave its caller.
class _CountingEntryCrypto extends EntryV2CryptoService {
  int secretReads = 0;
  int indexReads = 0;
  @override
  Future<Map<String, dynamic>> openMemberIndex({
    required Map<String, dynamic> envelope,
    required Uint8List vaultKey,
  }) {
    indexReads++;
    return super.openMemberIndex(envelope: envelope, vaultKey: vaultKey);
  }

  @override
  Future<Map<String, dynamic>> openMemberSecret({
    required Map<String, dynamic> entryKey,
    required Map<String, dynamic> memberSecret,
    required Uint8List vaultKey,
  }) {
    secretReads++;
    return super.openMemberSecret(
      entryKey: entryKey,
      memberSecret: memberSecret,
      vaultKey: vaultKey,
    );
  }
}

class _CountingCurrentEntries extends LocalCurrentEntryService {
  _CountingCurrentEntries({
    required super.reader,
    required super.authorityProvider,
    required super.vaultKeys,
    required super.entryCrypto,
    required super.canonicalAdapter,
  });
  final reads = <(String, String)>[];
  @override
  Future<LocalCurrentEntryReveal> revealCurrentWithAuthority({
    required String vaultId,
    required String entryId,
    required Uint8List memberPrivateKey,
  }) {
    reads.add((vaultId, entryId));
    return super.revealCurrentWithAuthority(
      vaultId: vaultId,
      entryId: entryId,
      memberPrivateKey: memberPrivateKey,
    );
  }
}

class _CountingVaultKeys extends VaultRotationCryptoService {
  int opens = 0;

  @override
  Future<Uint8List> openMemberVaultKey(
    Map<String, dynamic> envelope,
    Uint8List memberPrivateKey, {
    String? expectedOrganizationId,
    String? expectedVaultId,
    int? expectedVaultKeyVersion,
    int? expectedMemberKeyGeneration,
  }) {
    opens++;
    return super.openMemberVaultKey(
      envelope,
      memberPrivateKey,
      expectedOrganizationId: expectedOrganizationId,
      expectedVaultId: expectedVaultId,
      expectedVaultKeyVersion: expectedVaultKeyVersion,
      expectedMemberKeyGeneration: expectedMemberKeyGeneration,
    );
  }
}
