import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_preparation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_cache_bridge.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_incremental_publisher.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_incremental.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_record.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class _PreparationStorage extends SecureTokenStorage {
  _PreparationStorage() : super(const FlutterSecureStorage());
  int revision = 0;
  @override
  int get authorityRevision => revision;
}

class _PreparationProvider extends MemberSyncSessionAuthorityProvider {
  _PreparationProvider(this.read, SecureTokenStorage storage) : super(storage);
  final Future<MemberSyncSessionAuthority> Function() read;
  @override
  Future<MemberSyncSessionAuthority> current() => read();
}

class _Reader extends Mock implements MemberAutoFillMetadataReader {}

class _Authority extends Mock implements MemberSyncSessionAuthorityProvider {}

class _Entries extends Mock implements LocalCurrentEntryService {}

class _Bridge extends Mock implements AutoFillIncrementalCacheBridge {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Reader reader;
  late _Authority authority;
  late _Entries entries;
  late _Bridge bridge;
  late AutoFillIncrementalPublisher publisher;
  late _PreparationStorage preparationStorage;
  late MemberOfflineAccessContext context;
  late MemberSyncSessionAuthority claims;
  late List<MemberIndexEntry> indexes;
  late MemberAutoFillMetadata metadata;
  var reveals = 0;
  var fullCalls = 0;
  var revision = 0;
  final deltas = <List<AutoFillRecord>>[];
  final removals = <List<AutoFillEntryCoordinate>>[];

  MemberIndexEntry index(int n, {String revision = '1'}) => MemberIndexEntry(
    entryId: 'entry-$n',
    entryType: 1,
    memberLabel: 'Synthetic $n',
    searchFields: const [],
    revision: revision,
    currentKeyVersion: 1,
    state: MemberEntryState.active,
    autofillDomains: const ['example.invalid'],
  );
  void snapshot({int publicationRevision = 0, String sequence = '1'}) =>
      metadata = MemberAutoFillMetadata(
        readGeneration: 0,
        publicationRevision: publicationRevision,
        vaults: {
          context.vaultId: MemberAutoFillVaultMetadata(
            context: context,
            sequence: sequence,
            entries: List.of(indexes),
          ),
        },
      );

  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(const AutoFillCacheBase(generation: 1, revision: 1));
    registerFallbackValue(
      const MemberSyncSessionAuthority(
        principalId: 'p',
        organizationId: 'o',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      ),
    );
    registerFallbackValue(
      const MemberAutoFillMetadata(
        readGeneration: 0,
        publicationRevision: 0,
        vaults: {},
      ),
    );
    final emptyManifest = AutoFillCacheManifest(
      principalId: 'p',
      organizationId: 'o',
      organizationMembershipGeneration: '1',
      offlinePolicy: '24h',
      offlinePolicyVersion: 1,
      vaults: {},
    );
    registerFallbackValue(emptyManifest);
    registerFallbackValue(
      AutoFillCachePayload(manifest: emptyManifest, records: []),
    );
  });
  setUp(() async {
    context = MemberSnapshotPage.fromJson(
      Map<String, dynamic>.from(
        (jsonDecode(
                  File(
                    'test/fixtures/current_member_entry_sync_v2/valid-snapshot.json',
                  ).readAsStringSync(),
                )
                as Map)['response']
            as Map,
      ),
    ).accessContext;
    claims = MemberSyncSessionAuthority(
      principalId: context.principalId,
      organizationId: context.organizationId,
      organizationMembershipGeneration:
          context.organizationMembershipGeneration,
      offlinePolicy: context.offlinePolicy,
      offlinePolicyVersion: context.offlinePolicyVersion,
    );
    indexes = List.generate(160, index);
    snapshot();
    reveals = 0;
    fullCalls = 0;
    revision = 0;
    deltas.clear();
    removals.clear();
    reader = _Reader();
    authority = _Authority();
    entries = _Entries();
    bridge = _Bridge();
    when(() => authority.current()).thenAnswer((_) async => claims);
    when(
      () => authority.sessionRevision,
    ).thenAnswer((_) => preparationStorage.revision);
    when(
      () => reader.canReuseAutoFillPublication(
        readGeneration: any(named: 'readGeneration'),
        contentRevision: any(named: 'contentRevision'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenReturn(false);
    preparationStorage = _PreparationStorage();
    final preparationProvider = _PreparationProvider(
      authority.current,
      preparationStorage,
    );
    registerFallbackValue(await preparationProvider.captureForPreparation());
    when(
      () => authority.captureForPreparation(),
    ).thenAnswer((_) => preparationProvider.captureForPreparation());
    when(
      () => reader.readAutoFillMetadata(
        vaultIds: any(named: 'vaultIds'),
        authority: any(named: 'authority'),
      ),
    ).thenAnswer((_) async => metadata);
    when(
      () => reader.revalidateAutoFillMetadata(
        any(),
        authority: any(named: 'authority'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => bridge.beginWriterSession(sessionToken: any(named: 'sessionToken')),
    ).thenAnswer((_) async => 1);
    when(
      () => bridge.endWriterSession(writerEpoch: any(named: 'writerEpoch')),
    ).thenAnswer((_) async {});
    when(
      () => bridge.replaceCacheV3(
        any(),
        sessionToken: any(named: 'sessionToken'),
        writerEpoch: any(named: 'writerEpoch'),
        base: any(named: 'base'),
        releasingDenies: any(named: 'releasingDenies'),
        validatePublication: any(named: 'validatePublication'),
      ),
    ).thenAnswer((_) async {
      fullCalls++;
      return AutoFillCacheBase(generation: 7, revision: ++revision);
    });
    when(
      () => bridge.denyEntries(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        entries: any(named: 'entries'),
      ),
    ).thenAnswer(
      (_) async => AutoFillScopedDenial(
        base: AutoFillCacheBase(generation: 7, revision: ++revision),
        token: 'owner-$revision',
      ),
    );
    when(
      () => bridge.applyCacheDelta(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        manifest: any(named: 'manifest'),
        upserts: any(named: 'upserts'),
        removals: any(named: 'removals'),
        releasingDenies: any(named: 'releasingDenies'),
        validatePublication: any(named: 'validatePublication'),
      ),
    ).thenAnswer((call) async {
      deltas.add(
        List.of(call.namedArguments[#upserts] as List<AutoFillRecord>),
      );
      removals.add(
        List.of(
          call.namedArguments[#removals] as List<AutoFillEntryCoordinate>,
        ),
      );
      return AutoFillCacheBase(generation: 7, revision: ++revision);
    });
    when(
      () => entries.revealPreparedWithAuthority(
        authority: any(named: 'authority'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((call) async {
      reveals++;
      final entry = indexes.singleWhere(
        (entry) => entry.entryId == call.namedArguments[#entryId],
      );
      return LocalCurrentEntryReveal(
        snapshot: CanonicalEntrySnapshot(
          entry: {
            'id': entry.entryId,
            'organizationId': context.organizationId,
            'vaultId': context.vaultId,
            'state': 'active',
            'currentRevision': entry.revision,
            'currentKeyVersion': 1,
          },
          secret: {},
          payload: {'username': 'synthetic', 'password': 'synthetic-only'},
        ),
        accessContext: context,
      );
    });
    publisher = AutoFillIncrementalPublisher(
      bridge: bridge,
      metadata: reader,
      authority: authority,
      entries: entries,
    );
  });

  Future<void> publish() => publisher.synchronize(
    privateKey: Uint8List(32),
    vaultIds: [context.vaultId],
    isCurrent: () => true,
    onProgress: (_) {},
  );

  void admitUnchangedCheck() {
    when(
      () => reader.canReuseAutoFillPublication(
        readGeneration: any(named: 'readGeneration'),
        contentRevision: any(named: 'contentRevision'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenReturn(true);
  }

  test(
    'validated no-op accepts same native revision and reports checking',
    () async {
      await publisher.beginSession(7);
      await publish();
      admitUnchangedCheck();
      when(
        () => bridge.applyCacheDelta(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          manifest: any(named: 'manifest'),
          upserts: any(named: 'upserts'),
          removals: any(named: 'removals'),
          releasingDenies: any(named: 'releasingDenies'),
          validatePublication: any(named: 'validatePublication'),
        ),
      ).thenAnswer(
        (call) async => call.namedArguments[#base] as AutoFillCacheBase,
      );
      final phases = <AutoFillPreparationPhase>[];
      await publisher.synchronize(
        privateKey: Uint8List(32),
        vaultIds: [context.vaultId],
        isCurrent: () => true,
        onProgress: (value) => phases.add(value.phase),
      );
      expect(phases, [
        AutoFillPreparationPhase.checking,
        AutoFillPreparationPhase.checking,
        AutoFillPreparationPhase.ready,
      ]);
      expect(reveals, 160);
    },
  );

  test('unknown commit is denied before metadata await', () async {
    await publisher.beginSession(7);
    await publish();
    clearInteractions(bridge);
    final held = Completer<MemberAutoFillMetadata>();
    when(
      () => reader.readAutoFillMetadata(
        vaultIds: any(named: 'vaultIds'),
        authority: any(named: 'authority'),
      ),
    ).thenAnswer((_) => held.future);
    final operation = publish();
    await Future<void>.delayed(Duration.zero);
    verify(
      () => bridge.denyEntries(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        entries: any(named: 'entries'),
      ),
    ).called(1);
    held.complete(metadata);
    await operation;
  });

  test(
    'ordinary lock cancels held unchanged check without denying the provider',
    () async {
      await publisher.beginSession(7);
      await publish();
      clearInteractions(bridge);
      admitUnchangedCheck();
      final held = Completer<MemberAutoFillMetadata>();
      when(
        () => reader.readAutoFillMetadata(
          vaultIds: any(named: 'vaultIds'),
          authority: any(named: 'authority'),
        ),
      ).thenAnswer((_) => held.future);
      final operation = publish();
      final rejected = expectLater(operation, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await publisher.endSession();
      held.complete(metadata);
      await rejected;
      verifyNever(
        () => bridge.denyEntries(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          entries: any(named: 'entries'),
        ),
      );
      verifyNever(
        () => bridge.applyCacheDelta(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          manifest: any(named: 'manifest'),
          upserts: any(named: 'upserts'),
          removals: any(named: 'removals'),
          releasingDenies: any(named: 'releasingDenies'),
          validatePublication: any(named: 'validatePublication'),
        ),
      );
    },
  );

  test('token authority change cannot use the unchanged lane', () async {
    await publisher.beginSession(7);
    await publish();
    admitUnchangedCheck();
    preparationStorage.revision++;
    clearInteractions(bridge);
    await publish();
    verify(
      () => bridge.denyEntries(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        entries: any(named: 'entries'),
      ),
    ).called(1);
  });

  test('pending mutation owner cannot use unchanged acknowledgement', () async {
    await publisher.beginSession(7);
    await publish();
    admitUnchangedCheck();
    await publisher.deny(null);
    when(
      () => bridge.applyCacheDelta(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        manifest: any(named: 'manifest'),
        upserts: any(named: 'upserts'),
        removals: any(named: 'removals'),
        releasingDenies: any(named: 'releasingDenies'),
        validatePublication: any(named: 'validatePublication'),
      ),
    ).thenAnswer(
      (call) async => call.namedArguments[#base] as AutoFillCacheBase,
    );
    await expectLater(publish(), throwsFormatException);
  });

  test(
    'unchanged refresh does not deny previously published credentials',
    () async {
      await publisher.beginSession(7);
      await publish();
      clearInteractions(bridge);
      when(
        () => reader.canReuseAutoFillPublication(
          readGeneration: any(named: 'readGeneration'),
          contentRevision: any(named: 'contentRevision'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenReturn(true);
      await publish();
      verifyNever(
        () => bridge.denyEntries(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          entries: any(named: 'entries'),
        ),
      );
      expect(reveals, 160);
    },
  );

  test(
    'initial publication survives a same-authority lease renewal without extending its lease',
    () async {
      final original = context;
      await publisher.beginSession(7);
      await publisher.synchronize(
        privateKey: Uint8List(32),
        vaultIds: [context.vaultId],
        isCurrent: () => true,
        onProgress: (progress) {
          if (progress.examined == 80 && context == original) {
            context = MemberOfflineAccessContext.fromJson({
              ...original.toJson(),
              'issuedAt': original.issuedAt
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
              'notAfter': original.notAfter
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
            });
            snapshot();
          }
        },
      );
      expect(reveals, 160);
      expect(fullCalls, 1);
      final payload =
          verify(
                () => bridge.replaceCacheV3(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                  writerEpoch: any(named: 'writerEpoch'),
                  base: any(named: 'base'),
                  releasingDenies: any(named: 'releasingDenies'),
                  validatePublication: any(named: 'validatePublication'),
                ),
              ).captured.single
              as AutoFillCachePayload;
      expect(
        payload.manifest.vaults[original.vaultId]!.notAfter,
        original.notAfter,
      );
    },
  );

  for (final change in [
    'entry',
    'addition',
    'removal',
    'sequence',
    'key',
    'membership',
  ]) {
    test(
      'lease refresh cannot conceal $change change before publication',
      () async {
        await publisher.beginSession(7);
        await expectLater(
          publisher.synchronize(
            privateKey: Uint8List(32),
            vaultIds: [context.vaultId],
            isCurrent: () => true,
            onProgress: (progress) {
              if (progress.phase != AutoFillPreparationPhase.preparing ||
                  progress.examined != 160) {
                return;
              }
              switch (change) {
                case 'entry':
                  indexes[0] = index(0, revision: '2');
                case 'addition':
                  indexes.add(index(160));
                case 'removal':
                  indexes.removeLast();
                case 'key':
                  context = MemberOfflineAccessContext.fromJson({
                    ...context.toJson(),
                    'vaultKeyVersion': context.vaultKeyVersion + 1,
                  });
                case 'membership':
                  context = MemberOfflineAccessContext.fromJson({
                    ...context.toJson(),
                    'organizationMembershipGeneration': '99',
                  });
              }
              snapshot(
                publicationRevision: 1,
                sequence: change == 'sequence' ? '2' : '1',
              );
            },
          ),
          throwsA(isA<StateError>()),
        );
        expect(fullCalls, 0);
      },
    );
  }

  test(
    'earlier overlapping lease is preserved as a whole authenticated context',
    () async {
      final original = context;
      final earlier = MemberOfflineAccessContext.fromJson({
        ...original.toJson(),
        'issuedAt': original.issuedAt
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
        'notAfter': original.notAfter
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
      });
      await publisher.beginSession(7);
      await publisher.synchronize(
        privateKey: Uint8List(32),
        vaultIds: [context.vaultId],
        isCurrent: () => true,
        onProgress: (p) {
          if (p.examined == 80) {
            context = earlier;
            snapshot(publicationRevision: 1);
          }
        },
      );
      final payload =
          verify(
                () => bridge.replaceCacheV3(
                  captureAny(),
                  sessionToken: any(named: 'sessionToken'),
                  writerEpoch: any(named: 'writerEpoch'),
                  base: any(named: 'base'),
                  releasingDenies: any(named: 'releasingDenies'),
                  validatePublication: any(named: 'validatePublication'),
                ),
              ).captured.single
              as AutoFillCachePayload;
      expect(
        payload.manifest.vaults[original.vaultId]!.issuedAt,
        earlier.issuedAt,
      );
      expect(
        payload.manifest.vaults[original.vaultId]!.notAfter,
        earlier.notAfter,
      );
    },
  );

  for (final reverse in [false, true]) {
    test(
      'disjoint renewal chain is rejected regardless of order reverse=$reverse',
      () async {
        final original = context;
        final offsets = [
          const Duration(hours: 2),
          -original.leaseDuration + const Duration(hours: 1),
        ];
        if (reverse) offsets.setAll(0, offsets.reversed.toList());
        await publisher.beginSession(7);
        await expectLater(
          publisher.synchronize(
            privateKey: Uint8List(32),
            vaultIds: [context.vaultId],
            isCurrent: () => true,
            onProgress: (p) {
              if (p.examined == 40 || p.examined == 80) {
                final offset = offsets[p.examined == 40 ? 0 : 1];
                context = MemberOfflineAccessContext.fromJson({
                  ...original.toJson(),
                  'issuedAt': original.issuedAt.add(offset).toIso8601String(),
                  'notAfter': original.notAfter.add(offset).toIso8601String(),
                });
                snapshot(publicationRevision: p.examined);
              }
            },
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'boundary',
              'Disjoint AutoFill authority leases',
            ),
          ),
        );
        expect(fullCalls, 0);
      },
    );
  }

  test(
    'fresh lease cannot publish after the preserved lease expires',
    () async {
      final original = context;
      var now = original.issuedAt;
      when(() => reader.validateAutoFillPublication(any())).thenAnswer((call) {
        final candidate =
            call.positionalArguments.single as MemberAutoFillMetadata;
        if (candidate.publicationRevision != metadata.publicationRevision ||
            candidate.vaults.values.any(
              (vault) => !now.isBefore(vault.context.notAfter),
            )) {
          throw StateError('expired publication authority');
        }
      });
      await publisher.beginSession(7);
      await expectLater(
        publisher.synchronize(
          privateKey: Uint8List(32),
          vaultIds: [context.vaultId],
          isCurrent: () => true,
          onProgress: (p) {
            if (p.phase == AutoFillPreparationPhase.preparing &&
                p.examined == 80) {
              context = MemberOfflineAccessContext.fromJson({
                ...original.toJson(),
                'issuedAt': original.issuedAt
                    .add(const Duration(minutes: 2))
                    .toIso8601String(),
                'notAfter': original.notAfter
                    .add(const Duration(minutes: 2))
                    .toIso8601String(),
              });
              snapshot(publicationRevision: 1);
            }
            if (p.phase == AutoFillPreparationPhase.publishing) {
              now = original.notAfter;
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(fullCalls, 0);
    },
  );

  for (final phase in ['between-reveals', 'publishing', 'acknowledgement']) {
    test(
      'token authority change at $phase cannot acknowledge publication',
      () async {
        await publisher.beginSession(7);
        final phases = <AutoFillPreparationPhase>[];
        if (phase == 'acknowledgement') {
          when(
            () => bridge.replaceCacheV3(
              any(),
              sessionToken: any(named: 'sessionToken'),
              writerEpoch: any(named: 'writerEpoch'),
              base: any(named: 'base'),
              releasingDenies: any(named: 'releasingDenies'),
              validatePublication: any(named: 'validatePublication'),
            ),
          ).thenAnswer((_) async {
            preparationStorage.revision++;
            return const AutoFillCacheBase(generation: 7, revision: 1);
          });
        }
        await expectLater(
          publisher.synchronize(
            privateKey: Uint8List(32),
            vaultIds: [context.vaultId],
            isCurrent: () => true,
            onProgress: (p) {
              phases.add(p.phase);
              if ((phase == 'between-reveals' &&
                      p.phase == AutoFillPreparationPhase.preparing &&
                      p.examined == 1) ||
                  (phase == 'publishing' &&
                      p.phase == AutoFillPreparationPhase.publishing)) {
                preparationStorage.revision++;
              }
            },
          ),
          throwsA(isA<StateError>()),
        );
        expect(phases, isNot(contains(AutoFillPreparationPhase.ready)));
        expect(
          await publisher.deny({
            AutoFillEntryCoordinate(
              vaultId: context.vaultId,
              entryId: 'entry-0',
            ),
          }),
          isFalse,
        );
        if (phase != 'acknowledgement') expect(fullCalls, 0);
      },
    );
  }

  test('one changed Entry reveals one body and removal reveals none', () async {
    await publisher.beginSession(7);
    await publish();
    expect(reveals, 160);
    expect(fullCalls, 1);
    indexes[12] = index(12, revision: '2');
    snapshot();
    reveals = 0;
    await publish();
    expect(reveals, 1);
    expect(fullCalls, 1);
    expect(deltas.single.map((record) => record.id), ['entry-12']);
    indexes.removeAt(12);
    snapshot();
    reveals = 0;
    await publish();
    expect(reveals, 0);
    expect(removals.last.single.entryId, 'entry-12');
  });

  test(
    'native recovery condition reaches service before any full replacement',
    () async {
      await publisher.beginSession(7);
      await publish();
      when(
        () => bridge.applyCacheDelta(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          manifest: any(named: 'manifest'),
          upserts: any(named: 'upserts'),
          removals: any(named: 'removals'),
          releasingDenies: any(named: 'releasingDenies'),
          validatePublication: any(named: 'validatePublication'),
        ),
      ).thenThrow(PlatformException(code: 'AUTOFILL_FULL_RECOVERY_REQUIRED'));
      reveals = 0;
      await expectLater(
        publish(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'AUTOFILL_FULL_RECOVERY_REQUIRED',
          ),
        ),
      );
      expect(fullCalls, 1);
      expect(reveals, 0);
    },
  );

  test(
    'last removal publishes a complete empty catalog without body reads',
    () async {
      await publisher.beginSession(7);
      await publish();
      indexes.clear();
      snapshot();
      reveals = 0;
      await publish();
      expect(reveals, 0);
      expect(fullCalls, 1);
      expect(removals.single, hasLength(160));
      expect(deltas.single, isEmpty);
    },
  );

  test('failed delta never becomes the acknowledged base', () async {
    await publisher.beginSession(7);
    await publish();
    when(
      () => bridge.applyCacheDelta(
        base: any(named: 'base'),
        writerEpoch: any(named: 'writerEpoch'),
        manifest: any(named: 'manifest'),
        upserts: any(named: 'upserts'),
        removals: any(named: 'removals'),
        releasingDenies: any(named: 'releasingDenies'),
        validatePublication: any(named: 'validatePublication'),
      ),
    ).thenThrow(PlatformException(code: 'AUTOFILL_STALE_BASE'));
    await expectLater(publish(), throwsA(isA<PlatformException>()));
    expect(fullCalls, 1);
  });

  test(
    'scope denial is native-owned and missing base never means empty',
    () async {
      expect(await publisher.deny(null), isFalse);
      await publisher.beginSession(7);
      await publish();
      expect(
        await publisher.deny({
          AutoFillEntryCoordinate(
            vaultId: context.vaultId,
            entryId: 'entry-12',
          ),
        }),
        isTrue,
      );
      verify(
        () => bridge.denyEntries(
          base: any(named: 'base'),
          writerEpoch: 1,
          entries: [
            AutoFillEntryCoordinate(
              vaultId: context.vaultId,
              entryId: 'entry-12',
            ),
          ],
        ),
      ).called(1);
      await publisher.endSession();
      expect(await publisher.deny(null), isFalse);
    },
  );

  test(
    'new-entry mutation checks CAS while native publication reply is delayed',
    () async {
      await publisher.beginSession(7);
      await publish();
      indexes.add(index(160));
      snapshot();
      final committed = Completer<void>();
      final reply = Completer<AutoFillCacheBase>();
      var current = true;
      when(
        () => bridge.applyCacheDelta(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          manifest: any(named: 'manifest'),
          upserts: any(named: 'upserts'),
          removals: any(named: 'removals'),
          releasingDenies: any(named: 'releasingDenies'),
          validatePublication: any(named: 'validatePublication'),
        ),
      ).thenAnswer((_) {
        ++revision;
        committed.complete();
        return reply.future;
      });
      final publication = publisher.synchronize(
        privateKey: Uint8List(32),
        vaultIds: [context.vaultId],
        isCurrent: () => current,
        onProgress: (_) {},
      );
      final rejected = expectLater(publication, throwsStateError);
      await committed.future;
      current = false; // service invalidation generation changes synchronously
      when(
        () => bridge.denyEntries(
          base: any(named: 'base'),
          writerEpoch: any(named: 'writerEpoch'),
          entries: any(named: 'entries'),
        ),
      ).thenAnswer((call) async {
        expect(
          (call.namedArguments[#base] as AutoFillCacheBase).revision,
          lessThan(revision),
        );
        throw PlatformException(code: 'AUTOFILL_STALE_BASE');
      });
      await expectLater(
        publisher.deny({
          AutoFillEntryCoordinate(
            vaultId: context.vaultId,
            entryId: 'entry-160',
          ),
        }),
        throwsA(isA<PlatformException>()),
      );
      verify(
        () => bridge.denyEntries(
          base: any(named: 'base'),
          writerEpoch: 1,
          entries: const [],
        ),
      ).called(1);
      reply.complete(AutoFillCacheBase(generation: 7, revision: revision));
      await rejected;
    },
  );

  test(
    'durable metadata change during final authority read prevents owned-deny release',
    () async {
      await publisher.beginSession(7);
      await publish();
      await publisher.deny({
        AutoFillEntryCoordinate(vaultId: context.vaultId, entryId: 'entry-0'),
      });
      indexes[0] = index(0, revision: '2');
      snapshot();
      final finalRead = Completer<void>();
      final continueRead = Completer<MemberSyncSessionAuthority>();
      var reads = 0;
      var newerMetadataCommitted = false;
      when(() => authority.current()).thenAnswer((_) {
        if (++reads == 2) {
          finalRead.complete();
          return continueRead.future;
        }
        return Future.value(claims);
      });
      when(() => reader.validateAutoFillPublication(any())).thenAnswer((_) {
        if (newerMetadataCommitted) {
          throw const LocalMemberEntryReadInvalidatedException();
        }
      });
      final publication = publish();
      final result = expectLater(
        publication,
        throwsA(isA<LocalMemberEntryReadInvalidatedException>()),
      );
      await finalRead.future;
      // An owned repair deny queues this commit instead of starting another
      // service publication, so its existing isCurrent closure stays true.
      newerMetadataCommitted = true;
      continueRead.complete(claims);
      await result;
      expect(deltas, isEmpty);
      expect(fullCalls, 1);
    },
  );

  for (final unchanged in [false, true]) {
    test(
      'metadata change before acknowledgement never reports ready (unchanged=$unchanged)',
      () async {
        await publisher.beginSession(7);
        await publish();
        if (unchanged) admitUnchangedCheck();
        final entered = Completer<void>();
        final reply = Completer<AutoFillCacheBase>();
        var obsolete = false;
        when(() => reader.validateAutoFillPublication(any())).thenAnswer((_) {
          if (obsolete) throw const LocalMemberEntryReadInvalidatedException();
        });
        when(
          () => bridge.applyCacheDelta(
            base: any(named: 'base'),
            writerEpoch: any(named: 'writerEpoch'),
            manifest: any(named: 'manifest'),
            upserts: any(named: 'upserts'),
            removals: any(named: 'removals'),
            releasingDenies: any(named: 'releasingDenies'),
            validatePublication: any(named: 'validatePublication'),
          ),
        ).thenAnswer((_) {
          entered.complete();
          return reply.future;
        });
        final phases = <String>[];
        final operation = publisher.synchronize(
          privateKey: Uint8List(32),
          vaultIds: [context.vaultId],
          isCurrent: () => true,
          onProgress: (state) => phases.add(state.phase.name),
        );
        final result = expectLater(
          operation,
          throwsA(isA<LocalMemberEntryReadInvalidatedException>()),
        );
        await entered.future;
        obsolete = true;
        reply.complete(
          AutoFillCacheBase(
            generation: 7,
            revision: unchanged ? revision : ++revision,
          ),
        );
        await result;
        expect(phases, isNot(contains('ready')));
      },
    );
  }

  for (final delta in [false, true]) {
    test(
      'production bridge rechecks metadata after availability await (delta=$delta)',
      () async {
        const channel = MethodChannel('incremental-publication-fence');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final submitted = <String>[];
        var nativeRevision = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'beginWriterSession') return 1;
          if (call.method == 'endWriterSession') return null;
          if (call.method == 'denyEntries') {
            return {
              'base': {'generation': 7, 'revision': ++nativeRevision},
              'denyToken': 'owner-$nativeRevision',
            };
          }
          submitted.add(call.method);
          return {'generation': 7, 'revision': ++nativeRevision};
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final production = AutoFillIncrementalPublisher(
          bridge: MethodChannelAutoFillCacheBridge(
            channel: channel,
            availabilityProbe: () async => true,
          ),
          metadata: reader,
          authority: authority,
          entries: entries,
        );
        await production.beginSession(7);
        if (delta) {
          await production.synchronize(
            privateKey: Uint8List(32),
            vaultIds: [context.vaultId],
            isCurrent: () => true,
            onProgress: (_) {},
          );
          indexes[0] = index(0, revision: '2');
          snapshot();
        }
        submitted.clear();
        var obsolete = false;
        when(() => reader.validateAutoFillPublication(any())).thenAnswer((_) {
          if (obsolete) throw const LocalMemberEntryReadInvalidatedException();
        });
        await expectLater(
          production.synchronize(
            privateKey: Uint8List(32),
            vaultIds: [context.vaultId],
            isCurrent: () => true,
            onProgress: (progress) {
              if (progress.phase.name == 'publishing') {
                scheduleMicrotask(() {
                  obsolete = true;
                });
              }
            },
          ),
          throwsA(isA<LocalMemberEntryReadInvalidatedException>()),
        );
        expect(submitted, isEmpty);
      },
    );
  }

  test(
    'lock during reveal cannot publish or retain writer capability',
    () async {
      await publisher.beginSession(7);
      when(
        () => reader.revalidateAutoFillMetadata(
          any(),
          authority: any(named: 'authority'),
        ),
      ).thenAnswer((_) async {
        await publisher.endSession();
      });
      await expectLater(publish(), throwsStateError);
      expect(fullCalls, 0);
      expect(deltas, isEmpty);
      verify(() => bridge.endWriterSession(writerEpoch: 1)).called(1);
    },
  );
}
