import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/import_wizard_cubit.dart';

class _MockRepository extends Mock implements EntryRepository {}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late _MockRepository repository;

  const csv = 'name,url,username,password,note\n'
      'GitHub,https://github.com,octocat,S3cr3t!,\n'
      'GitLab,https://gitlab.com,tux,hunter2,';
  final privateKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  setUpAll(() {
    registerFallbackValue(<ImportEntryDraft>[]);
    registerFallbackValue(<ImportEntryOverwrite>[]);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() => repository = _MockRepository());

  ImportWizardCubit build() =>
      ImportWizardCubit(repository: repository, vaultId: 'v-1');

  EntryEntity existing(String label) => EntryEntity(
        id: 'e-$label',
        vaultId: 'v-1',
        label: label,
        type: EntryType.credential,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  group('parseBytes', () {
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
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => [existing('GitHub')]);
        return build();
      },
      act: (c) => c.parseBytes(_bytes(csv)),
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>().having((s) => s.conflictCount, 'conflicts', 1),
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
    blocTest<ImportWizardCubit, ImportWizardState>(
      'streams progress then Success on the happy path',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(() => repository.importEntriesEncrypted(
              vaultId: any(named: 'vaultId'),
              format: any(named: 'format'),
              creates: any(named: 'creates'),
              overwrites: any(named: 'overwrites'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              chunkSize: any(named: 'chunkSize'),
              onProgress: any(named: 'onProgress'),
            )).thenAnswer((inv) async {
          final onProgress =
              inv.namedArguments[#onProgress] as void Function(int, int)?;
          onProgress?.call(2, 2);
          return const ImportResult(createdCount: 2, updatedCount: 0);
        });
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        await c.import(privateKey: privateKey);
      },
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>(),
        isA<ImportWizardImporting>()
            .having((s) => s.done, 'done', 0)
            .having((s) => s.total, 'total', 2),
        isA<ImportWizardImporting>().having((s) => s.done, 'done', 2),
        isA<ImportWizardSuccess>()
            .having((s) => s.createdCount, 'created', 2)
            .having((s) => s.updatedCount, 'updated', 0),
      ],
      verify: (_) {
        final captured = verify(() => repository.importEntriesEncrypted(
              vaultId: 'v-1',
              format: any(named: 'format'),
              creates: captureAny(named: 'creates'),
              overwrites: captureAny(named: 'overwrites'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              chunkSize: any(named: 'chunkSize'),
              onProgress: any(named: 'onProgress'),
            )).captured;
        final creates = captured[0] as List<ImportEntryDraft>;
        final overwrites = captured[1] as List<ImportEntryOverwrite>;
        expect(creates, hasLength(2));
        expect(overwrites, isEmpty);
      },
    );

    blocTest<ImportWizardCubit, ImportWizardState>(
      'maps a network EntryException to a network failure',
      build: () {
        when(() => repository.listEntries(any())).thenAnswer((_) async => []);
        when(() => repository.importEntriesEncrypted(
              vaultId: any(named: 'vaultId'),
              format: any(named: 'format'),
              creates: any(named: 'creates'),
              overwrites: any(named: 'overwrites'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              chunkSize: any(named: 'chunkSize'),
              onProgress: any(named: 'onProgress'),
            )).thenThrow(const EntryException(EntryErrorKind.networkError));
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        await c.import(privateKey: privateKey);
      },
      expect: () => [
        isA<ImportWizardParsing>(),
        isA<ImportWizardPreview>(),
        isA<ImportWizardImporting>(),
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
        when(() => repository.listEntries(any()))
            .thenAnswer((_) async => [existing('GitHub')]);
        when(() => repository.importEntriesEncrypted(
              vaultId: any(named: 'vaultId'),
              format: any(named: 'format'),
              creates: any(named: 'creates'),
              overwrites: any(named: 'overwrites'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              chunkSize: any(named: 'chunkSize'),
              onProgress: any(named: 'onProgress'),
            )).thenAnswer(
          (_) async => const ImportResult(createdCount: 1, updatedCount: 1),
        );
        return build();
      },
      act: (c) async {
        await c.parseBytes(_bytes(csv));
        c.setConflictStrategy(ImportConflictStrategy.overwrite);
        await c.import(privateKey: privateKey);
      },
      verify: (_) {
        final captured = verify(() => repository.importEntriesEncrypted(
              vaultId: any(named: 'vaultId'),
              format: any(named: 'format'),
              creates: captureAny(named: 'creates'),
              overwrites: captureAny(named: 'overwrites'),
              privateKey: any(named: 'privateKey'),
              wrappedVK: any(named: 'wrappedVK'),
              chunkSize: any(named: 'chunkSize'),
              onProgress: any(named: 'onProgress'),
            )).captured;
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
