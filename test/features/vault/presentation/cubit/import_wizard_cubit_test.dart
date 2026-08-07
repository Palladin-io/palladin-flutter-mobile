import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/domain/exceptions/grants_exceptions.dart';
import 'package:mobile_palladin/features/grants/domain/repositories/grants_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/entities/public_asset.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/repositories/public_asset_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/import_wizard_cubit.dart';

class _MockRepository extends Mock implements EntryRepository {}

class _MockGrantsRepository extends Mock implements GrantsRepository {}

class _CatalogRepository implements PublicAssetRepository {
  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    final assets = {
      for (final hostname in hostnames)
        hostname: PublicAsset(
          id: '11111111-1111-4111-8111-111111111111',
          type: 'websiteIcon',
          name: hostname,
          revision: 1,
          deliveryUrl: Uri.parse('https://assets.palladin.io/$hostname.png'),
        ),
    };
    return WebsiteIconEnsureResult(
      assets: assets,
      statuses: {
        for (final hostname in assets.keys)
          hostname: WebsiteIconEnsureStatus.ready,
      },
    );
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _DelayedCatalogRepository implements PublicAssetRepository {
  final reservation = Completer<WebsiteIconEnsureResult>();
  int calls = 0;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) {
    calls++;
    return reservation.future;
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late _MockRepository repository;
  late _MockGrantsRepository grantsRepository;

  const csv =
      'name,url,username,password,note\n'
      'GitHub,https://github.com,octocat,S3cr3t!,\n'
      'GitLab,https://gitlab.com,tux,hunter2,';
  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(<ImportEntryDraft>[]);
    registerFallbackValue(<ImportEntryOverwrite>[]);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    repository = _MockRepository();
    grantsRepository = _MockGrantsRepository();
    when(
      () => grantsRepository.listGrants(
        any(),
        status: any(named: 'status'),
        agentId: any(named: 'agentId'),
        cursor: any(named: 'cursor'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const GrantListPage(grants: []));
  });

  ImportWizardCubit build({PublicAssetRepository? catalogRepository}) =>
      ImportWizardCubit(
        repository: repository,
        grantsRepository: grantsRepository,
        vaultId: 'v-1',
        websiteIconService: WebsiteIconService(
          catalogRepository ?? _CatalogRepository(),
        ),
      );

  Grant grant(GrantScope scope) => Grant(
    id: 'g-1',
    vaultId: 'v-1',
    agentId: 'a-1',
    status: GrantStatus.active,
    scope: scope,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  EntryEntity existing(String label) => EntryEntity(
    id: 'e-$label',
    vaultId: 'v-1',
    label: label,
    type: EntryType.credential,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  group('parseBytes', () {
    test('lock clears state and suppresses a late parse result', () async {
      final grants = Completer<GrantListPage>();
      when(
        () => grantsRepository.listGrants(
          any(),
          status: any(named: 'status'),
          agentId: any(named: 'agentId'),
          cursor: any(named: 'cursor'),
          pageSize: any(named: 'pageSize'),
        ),
      ).thenAnswer((_) => grants.future);
      when(() => repository.listEntries(any())).thenAnswer((_) async => []);
      final cubit = build();
      final parse = cubit.parseBytes(_bytes(csv));

      cubit.clearSensitiveState();
      grants.complete(const GrantListPage(grants: []));
      await parse;

      expect(cubit.state, isA<ImportWizardInitial>());
      await cubit.close();
    });

    blocTest<ImportWizardCubit, ImportWizardState>(
      'emits Parsing then Preview for a recognised CSV',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>()
            .having((s) => s.items.length, 'items', 2)
            .having((s) => s.conflictCount, 'conflicts', 0),
      ],
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'flags an existing label as a conflict',
      build: () {
        when(
          () => repository.listEntries(any()),
        ).thenAnswer((_) async => [existing('GitHub')]);
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>().having(
          (s) => s.conflictCount,
          'conflicts',
          1,
        ),
      ],
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'blocks the import when the vault has an active FULL grant',
      build: () {
        when(
          () => grantsRepository.listGrants(
            any(),
            status: any(named: 'status'),
            agentId: any(named: 'agentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => GrantListPage(grants: [grant(GrantScope.full)]),
        );
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardFailure>().having(
          (s) => s.reason,
          'reason',
          ImportFailureReason.fullGrantsBlocked,
        ),
      ],
      verify: (_) => verifyNever(() => repository.listEntries(any())),
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'a granular grant does not block the import',
      build: () {
        when(
          () => grantsRepository.listGrants(
            any(),
            status: any(named: 'status'),
            agentId: any(named: 'agentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenAnswer(
          (_) async => GrantListPage(grants: [grant(GrantScope.granular)]),
        );
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>().having((s) => s.items.length, 'items', 2),
      ],
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'maps a grant-lookup network failure to network, not unrecognised file',
      build: () {
        when(
          () => grantsRepository.listGrants(
            any(),
            status: any(named: 'status'),
            agentId: any(named: 'agentId'),
            cursor: any(named: 'cursor'),
            pageSize: any(named: 'pageSize'),
          ),
        ).thenThrow(const GrantsException(GrantsErrorKind.networkError));
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardFailure>().having(
          (s) => s.reason,
          'reason',
          ImportFailureReason.network,
        ),
      ],
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'emits Failure for unrecognised binary input',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        return build();
      },
      act: (c) => c.parseBytes(Uint8List.fromList([0, 1, 2, 3])),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardFailure>().having(
          (s) => s.reason,
          'reason',
          ImportFailureReason.unrecognisedFile,
        ),
      ],
    );
  });

  group('import', () {
    test(
      'a second tap cannot start another import during icon reservation',
      () async {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => const ImportResult(createdCount: 2, updatedCount: 0),
        );
        final catalog = _DelayedCatalogRepository();
        final cubit = build(catalogRepository: catalog);
        await cubit.parseBytes(_bytes(csv));

        final first = cubit.import(
          privateKey: privateKey,
          untitledLabel: 'Untitled',
        );
        final second = cubit.import(
          privateKey: privateKey,
          untitledLabel: 'Untitled',
        );
        final assets = {
          for (final hostname in ['github.com', 'gitlab.com'])
            hostname: PublicAsset(
              id: '11111111-1111-4111-8111-111111111111',
              type: 'websiteIcon',
              name: hostname,
              revision: 1,
              deliveryUrl: Uri.parse(
                'https://assets.palladin.io/$hostname.png',
              ),
            ),
        };
        catalog.reservation.complete(
          WebsiteIconEnsureResult(
            assets: assets,
            statuses: {
              for (final hostname in assets.keys)
                hostname: WebsiteIconEnsureStatus.ready,
            },
          ),
        );
        await Future.wait([first, second]);

        expect(catalog.calls, 1);
        verify(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);
        await cubit.close();
      },
    );

    test('lock cancels icon preparation and releases import promptly', () async {
      when(() => repository.listEntries(any())).thenAnswer((_) async => []);
      final catalog = _DelayedCatalogRepository();
      final cubit = build(catalogRepository: catalog);
      await cubit.parseBytes(_bytes(csv));

      final importing = cubit.import(
        privateKey: privateKey,
        untitledLabel: 'Untitled',
      );
      while (catalog.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      cubit.clearSensitiveState();
      await importing.timeout(const Duration(seconds: 1));

      expect(cubit.state, isA<ImportWizardInitial>());
      verifyNever(
        () => repository.importEntriesEncrypted(
          vaultId: any(named: 'vaultId'),
          format: any(named: 'format'),
          creates: any(named: 'creates'),
          overwrites: any(named: 'overwrites'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
          chunkSize: any(named: 'chunkSize'),
          onProgress: any(named: 'onProgress'),
        ),
      );
      await cubit.close();
    });

    test('lock during upload suppresses progress and late success', () async {
      when(() => repository.listEntries(any())).thenAnswer((_) async => []);
      final upload = Completer<ImportResult>();
      void Function(int, int)? progress;
      when(
        () => repository.importEntriesEncrypted(
          vaultId: any(named: 'vaultId'),
          format: any(named: 'format'),
          creates: any(named: 'creates'),
          overwrites: any(named: 'overwrites'),
          privateKey: any(named: 'privateKey'),
          wrappedVK: any(named: 'wrappedVK'),
          chunkSize: any(named: 'chunkSize'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) {
        progress =
            invocation.namedArguments[#onProgress] as void Function(int, int)?;
        return upload.future;
      });
      final cubit = build();
      await cubit.parseBytes(_bytes(csv));
      final importing = cubit.import(
        privateKey: privateKey,
        untitledLabel: 'Untitled',
      );

      cubit.clearSensitiveState();
      progress?.call(1, 2);
      upload.complete(const ImportResult(createdCount: 2, updatedCount: 0));
      await importing;

      expect(cubit.state, isA<ImportWizardInitial>());
      await cubit.close();
    });

    blocTest<ImportWizardCubit, ImportWizardState>(
      'streams progress then Success on the happy path',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((inv) async {
          final onProgress =
              inv.namedArguments[#onProgress] as void Function(int, int)?;
          onProgress?.call(2, 2);
          return const ImportResult(createdCount: 2, updatedCount: 0);
        });
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        await c.import(privateKey: privateKey, untitledLabel: 'Untitled');
      },
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>(),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'done', 0)
            .having((s) => s.total, 'total', 2)
            .having((s) => s.phase, 'phase', ImportProgressPhase.icons),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'done', 2)
            .having((s) => s.phase, 'phase', ImportProgressPhase.icons),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'done', 0)
            .having((s) => s.phase, 'phase', ImportProgressPhase.entries),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'done', 2)
            .having((s) => s.phase, 'phase', ImportProgressPhase.entries),
        isA<ImportWizardSuccess>()
            .having((s) => s.createdCount, 'created', 2)
            .having((s) => s.updatedCount, 'updated', 0),
      ],
      verify: (_) {
        final captured = verify(
          () => repository.importEntriesEncrypted(
            vaultId: 'v-1',
            format: any(named: 'format'),
            creates: captureAny(named: 'creates'),
            overwrites: captureAny(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).captured;
        final creates = captured[0] as List<ImportEntryDraft>;
        final overwrites = captured[1] as List<ImportEntryOverwrite>;
        expect(creates, hasLength(2));
        expect(creates.map((draft) => draft.icon), [
          'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fgithub.com.png',
          'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fgitlab.com.png',
        ]);
        expect(overwrites, isEmpty);
      },
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'applies the localized untitled fallback to an unnamed entry',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => const ImportResult(createdCount: 1, updatedCount: 0),
        );
        return build();
      },
      act: (c) async {
        await c.parseBytes(
          _bytes('name,url,username,password,note\n,,,S3cr3t!,'),
        );
        await c.import(privateKey: privateKey, untitledLabel: 'No name');
      },
      verify: (_) {
        final captured = verify(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: captureAny(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).captured;
        final creates = captured[0] as List<ImportEntryDraft>;
        expect(creates, hasLength(1));
        expect(creates.first.label, 'No name');
      },
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'maps a network EntryException to a network failure',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenThrow(const EntryException(EntryErrorKind.networkError));
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        await c.import(privateKey: privateKey, untitledLabel: 'Untitled');
      },
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>(),
        isA<ImportWizardImporting>().having(
          (s) => s.phase,
          'phase',
          ImportProgressPhase.icons,
        ),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'ready icons', 2)
            .having((s) => s.phase, 'phase', ImportProgressPhase.icons),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'imported entries', 0)
            .having((s) => s.phase, 'phase', ImportProgressPhase.entries),
        isA<ImportWizardFailure>().having(
          (s) => s.reason,
          'reason',
          ImportFailureReason.network,
        ),
      ],
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'overwrite strategy routes conflicts to overwrites',
      build: () {
        when(
          () => repository.listEntries(any()),
        ).thenAnswer((_) async => [existing('GitHub')]);
        when(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: any(named: 'creates'),
            overwrites: any(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer(
          (_) async => const ImportResult(createdCount: 1, updatedCount: 1),
        );
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        c.setConflictStrategy(ImportConflictStrategy.overwrite);
        await c.import(privateKey: privateKey, untitledLabel: 'Untitled');
      },
      verify: (_) {
        final captured = verify(
          () => repository.importEntriesEncrypted(
            vaultId: any(named: 'vaultId'),
            format: any(named: 'format'),
            creates: captureAny(named: 'creates'),
            overwrites: captureAny(named: 'overwrites'),
            privateKey: any(named: 'privateKey'),
            wrappedVK: any(named: 'wrappedVK'),
            chunkSize: any(named: 'chunkSize'),
            onProgress: any(named: 'onProgress'),
          ),
        ).captured;
        final creates = captured[0] as List<ImportEntryDraft>;
        final overwrites = captured[1] as List<ImportEntryOverwrite>;
        // GitLab is new → create; GitHub collides → overwrite.
        expect(creates, hasLength(1));
        expect(overwrites, hasLength(1));
        expect(overwrites.first.entryId, 'e-GitHub');
      },
    );
  });
}
