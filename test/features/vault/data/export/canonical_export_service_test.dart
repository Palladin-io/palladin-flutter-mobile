import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/export/canonical_export_service.dart';
import 'package:mobile_palladin/features/vault/data/export/export_models.dart';
import 'package:mobile_palladin/features/vault/data/export/export_serializers.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_entry('fallback', MemberEntryState.active));
    registerFallbackValue(
      ExportRecord(
        entryId: 'fallback',
        name: 'fallback',
        entryType: '0',
        lifecycle: 'active',
        revision: '1',
        payload: <String, dynamic>{},
      ),
    );
    registerFallbackValue(<String, dynamic>{});
  });
  late _Index index;
  late _Canonical canonical;
  late _Session session;
  late _Entries entries;
  late _Writer writer;
  late CanonicalExportService service;

  setUp(() {
    index = _Index();
    canonical = _Canonical();
    session = _Session();
    entries = _Entries();
    writer = _Writer();
    service = CanonicalExportService(
      index: index,
      canonical: canonical,
      entries: entries,
      writerFactory: (_) => writer,
      pageSize: 2,
    );
    when(
      () => canonical.beginExportSession(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => session);
    when(() => session.close()).thenReturn(null);
    when(() => session.vaultId).thenReturn('v');
    when(
      () => writer.start(
        vaultId: any(named: 'vaultId'),
        vaultName: any(named: 'vaultName'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => writer.finish(),
    ).thenAnswer((_) async => '/protected/export.json');
    when(() => writer.abort()).thenAnswer((_) async {});
  });

  test('defaults to active current heads and decrypts sequentially', () async {
    final active1 = _entry('a', MemberEntryState.active);
    final archived = _entry('b', MemberEntryState.archived);
    final active2 = _entry('c', MemberEntryState.active);
    when(
      () => index.load(
        vaultId: 'v',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => [active2, archived, active1]);
    var concurrent = 0;
    var peak = 0;
    when(() => session.revealCurrent(any())).thenAnswer((invocation) async {
      concurrent++;
      peak = concurrent > peak ? concurrent : peak;
      await Future<void>.delayed(Duration.zero);
      concurrent--;
      final item = invocation.positionalArguments.single as MemberIndexEntry;
      return _snapshot(item);
    });
    final written = <String>[];
    when(() => writer.write(any())).thenAnswer((invocation) async {
      written.add(
        (invocation.positionalArguments.single as ExportRecord).entryId,
      );
    });

    final result = await service.export(
      vaultId: 'v',
      vaultName: 'Vault',
      options: const ExportOptions(format: ExportFormat.json),
      memberPrivateKey: Uint8List(32),
    );

    expect(result.entryCount, 2);
    expect(written, ['a', 'c']);
    expect(peak, 1);
    verifyNever(() => session.revealCurrent(archived));
    verify(() => session.close()).called(1);
  });

  test(
    'history is explicit, cursor bounded, and N+1 decrypt concurrency is one',
    () async {
      final active = _entry('a', MemberEntryState.active);
      when(
        () => index.load(
          vaultId: 'v',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => [active]);
      when(
        () => session.revealCurrent(active),
      ).thenAnswer((_) async => _snapshot(active));
      when(
        () => entries.getEntryHistory(
          'v',
          'a',
          beforeRevision: null,
          pageSize: 20,
        ),
      ).thenAnswer(
        (_) async => {
          'items': [_history('1'), _history('0')],
          'nextBeforeRevision': null,
        },
      );
      var concurrent = 0;
      var peak = 0;
      when(
        () => session.revealHistory(
          expected: active,
          historyItem: any(named: 'historyItem'),
        ),
      ).thenAnswer((invocation) async {
        concurrent++;
        peak = concurrent > peak ? concurrent : peak;
        await Future<void>.delayed(Duration.zero);
        concurrent--;
        final row =
            invocation.namedArguments[#historyItem] as Map<String, dynamic>;
        return _snapshot(active, revision: row['revision']! as String);
      });
      when(() => writer.write(any())).thenAnswer((_) async {});

      final result = await service.export(
        vaultId: 'v',
        vaultName: 'Vault',
        options: const ExportOptions(
          format: ExportFormat.csv,
          includeHistory: true,
        ),
        memberPrivateKey: Uint8List(32),
      );

      expect(result.entryCount, 2); // current revision 1 is de-duplicated
      expect(peak, 1);
      verify(
        () => entries.getEntryHistory(
          'v',
          'a',
          beforeRevision: null,
          pageSize: 20,
        ),
      ).called(1);
    },
  );

  test(
    'lock cancellation prevents plaintext publication and aborts staging',
    () async {
      final gate = Completer<List<MemberIndexEntry>>();
      when(
        () => index.load(
          vaultId: 'v',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) => gate.future);
      final future = service.export(
        vaultId: 'v',
        vaultName: 'Vault',
        options: const ExportOptions(format: ExportFormat.json),
        memberPrivateKey: Uint8List(32),
      );
      service.cancel();
      gate.complete([_entry('a', MemberEntryState.active)]);
      await expectLater(
        future,
        throwsA(
          isA<ExportException>().having(
            (e) => e.kind,
            'kind',
            ExportErrorKind.cancelled,
          ),
        ),
      );
      verifyNever(
        () => writer.start(
          vaultId: any(named: 'vaultId'),
          vaultName: any(named: 'vaultName'),
        ),
      );
    },
  );

  test('lock during append aborts before finalize', () async {
    final active = _entry('a', MemberEntryState.active);
    when(
      () => index.load(
        vaultId: 'v',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => [active]);
    when(
      () => session.revealCurrent(active),
    ).thenAnswer((_) async => _snapshot(active));
    final appendStarted = Completer<void>();
    final releaseAppend = Completer<void>();
    when(() => writer.write(any())).thenAnswer((_) async {
      appendStarted.complete();
      await releaseAppend.future;
    });
    final future = service.export(
      vaultId: 'v',
      vaultName: 'Vault',
      options: const ExportOptions(format: ExportFormat.json),
      memberPrivateKey: Uint8List(32),
    );
    await appendStarted.future;
    service.cancel();
    releaseAppend.complete();
    await expectLater(future, throwsA(isA<ExportException>()));
    verify(() => writer.abort()).called(1);
    verifyNever(() => writer.finish());
  });

  test('finalize failure aborts staging and exposes typed failure', () async {
    final active = _entry('a', MemberEntryState.active);
    when(
      () => index.load(
        vaultId: 'v',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => [active]);
    when(
      () => session.revealCurrent(active),
    ).thenAnswer((_) async => _snapshot(active));
    when(() => writer.write(any())).thenAnswer((_) async {});
    when(() => writer.finish()).thenThrow(Exception('path=/secret/password'));

    await expectLater(
      service.export(
        vaultId: 'v',
        vaultName: 'Vault',
        options: const ExportOptions(format: ExportFormat.json),
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<ExportException>().having(
          (error) => error.kind,
          'typed kind',
          ExportErrorKind.staging,
        ),
      ),
    );
    verify(() => writer.abort()).called(1);
  });
}

MemberIndexEntry _entry(String id, MemberEntryState state) => MemberIndexEntry(
  entryId: id,
  entryType: 1,
  memberLabel: 'Entry $id',
  searchFields: const [],
  revision: '1',
  state: state,
);

CanonicalEntrySnapshot _snapshot(MemberIndexEntry entry, {String? revision}) =>
    CanonicalEntrySnapshot(
      entry: {'currentRevision': revision ?? entry.revision},
      secret: {
        'memberLabel': entry.memberLabel,
        'revision': revision ?? entry.revision,
      },
      payload: {'password': 'secret'},
    );

Map<String, dynamic> _history(String revision) => {
  'revision': revision,
  'entryKey': <String, dynamic>{},
  'memberSecret': <String, dynamic>{},
};

class _Index extends Mock implements MemberEntryListLoader {}

class _Canonical extends Mock implements CanonicalEntryDetailService {}

class _Session extends Mock implements CanonicalEntryExportSession {}

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Writer extends Mock implements ExportWriter {}
