import '../support/credential_source_fixture.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_credential_source.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

void main() {
  late TestAutoFillIndex index;
  late TestAutoFillEntries entries;
  late AutoFillCredentialSource source;
  var authorized = true;
  void guard() {
    if (!authorized) throw StateError('Request invalidated');
  }

  setUpAll(() => registerFallbackValue(Uint8List(32)));
  setUp(() {
    authorized = true;
    index = TestAutoFillIndex()
      ..values = [
        syntheticAutoFillEntry('chosen'),
        syntheticAutoFillEntry('other'),
      ];
    entries = TestAutoFillEntries();
    source = AutoFillCredentialSource(
      memberIndex: index,
      localEntries: entries,
    );
  });

  Future<List<AutoFillCandidate>> candidates() => source.candidates(
    vaultIds: ['vault'],
    verifiedHosts: {'login.example.com'},
    validateRequest: guard,
  );

  test(
    'matches exact current credential metadata without opening any body',
    () async {
      index.values = [
        syntheticAutoFillEntry('chosen'),
        syntheticAutoFillEntry('sibling', domain: 'other.example.com'),
        syntheticAutoFillEntry('archived', state: MemberEntryState.archived),
        syntheticAutoFillEntry('corrupt', corrupt: true),
        syntheticAutoFillEntry('key', type: 0),
      ];
      expect((await candidates()).map((item) => item.entryId), ['chosen']);
      verifyZeroInteractions(entries);
    },
  );

  test(
    'rejects URL or cleartext request input instead of turning it into authority',
    () async {
      for (final host in [
        'http://login.example.com',
        'https://login.example.com',
        '*.example.com',
      ]) {
        await expectLater(
          source.candidates(
            vaultIds: ['vault'],
            verifiedHosts: {host},
            validateRequest: guard,
          ),
          throwsA(isA<AutoFillCredentialException>()),
        );
      }
      verifyZeroInteractions(entries);
    },
  );

  test('lock while waiting for index exposes no candidates', () async {
    index.waiting = () async {
      authorized = false;
    };
    await expectLater(candidates(), throwsStateError);
  });

  test(
    'manual candidates still exclude corrupt and noncredential entries',
    () async {
      index.values = [
        syntheticAutoFillEntry('chosen'),
        syntheticAutoFillEntry('foreign', domain: 'other.example.com'),
        syntheticAutoFillEntry('key', type: 0),
      ];
      expect(
        (await source.manualCandidates(
          vaultIds: ['vault'],
          validateRequest: guard,
        )).map((item) => item.entryId),
        ['chosen', 'foreign'],
      );
      verifyZeroInteractions(entries);
    },
  );

  test('opens only selected body and clears it after completion', () async {
    final selected = (await candidates()).first;
    final reveal = syntheticAutoFillReveal();
    when(
      () => entries.revealCurrentWithAuthority(
        vaultId: 'vault',
        entryId: 'chosen',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => reveal);
    AutoFillSelectedCredential? retained;
    await source.withCredential(
      candidate: selected,
      selectedHost: 'login.example.com',
      memberPrivateKey: Uint8List(32),
      validateRequest: guard,
      complete: (value) async {
        retained = value;
        expect(value.username, 'synthetic-user');
        expect(value.password, 'synthetic-password');
      },
    );
    expect(reveal.snapshot.payload, isEmpty);
    expect(reveal.snapshot.secret, isEmpty);
    expect(
      () => retained!.password,
      throwsA(isA<AutoFillCredentialException>()),
    );
    verify(
      () => entries.revealCurrentWithAuthority(
        vaultId: 'vault',
        entryId: 'chosen',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
    verifyNoMoreInteractions(entries);
  });

  test('a candidate cannot be moved into another source session', () async {
    final selected = (await candidates()).first;
    final other = AutoFillCredentialSource(
      memberIndex: index,
      localEntries: entries,
    );
    final reveal = syntheticAutoFillReveal();
    when(
      () => entries.revealCurrentWithAuthority(
        vaultId: 'vault',
        entryId: 'chosen',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => reveal);
    var completed = false;
    await expectLater(
      other.withCredential(
        candidate: selected,
        selectedHost: 'login.example.com',
        memberPrivateKey: Uint8List(32),
        validateRequest: guard,
        complete: (_) async {
          completed = true;
        },
      ),
      throwsA(isA<AutoFillCredentialException>()),
    );
    expect(completed, isFalse);
    verifyZeroInteractions(entries);
  });

  for (final invalid in ['vault', 'revision', 'organization', 'expiry']) {
    test('$invalid mismatch prevents credential delivery', () async {
      final selected = (await candidates()).first;
      final reveal = syntheticAutoFillReveal(expired: invalid == 'expiry');
      if (invalid == 'vault') reveal.snapshot.entry['vaultId'] = 'foreign';
      if (invalid == 'revision') reveal.snapshot.entry['currentRevision'] = '2';
      if (invalid == 'organization') {
        reveal.snapshot.entry['organizationId'] = 'foreign';
      }
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => reveal);
      var completed = false;
      await expectLater(
        source.withCredential(
          candidate: selected,
          selectedHost: 'login.example.com',
          memberPrivateKey: Uint8List(32),
          validateRequest: guard,
          complete: (_) async {
            completed = true;
          },
        ),
        throwsA(isA<AutoFillCredentialException>()),
      );
      expect(completed, isFalse);
      expect(reveal.snapshot.payload, isEmpty);
    });
  }

  test('failed native completion releases temporary credential data', () async {
    final selected = (await candidates()).first;
    final reveal = syntheticAutoFillReveal();
    when(
      () => entries.revealCurrentWithAuthority(
        vaultId: 'vault',
        entryId: 'chosen',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => reveal);
    await expectLater(
      source.withCredential(
        candidate: selected,
        selectedHost: 'login.example.com',
        memberPrivateKey: Uint8List(32),
        validateRequest: guard,
        complete: (_) async {
          throw StateError('Cancelled');
        },
      ),
      throwsStateError,
    );
    expect(reveal.snapshot.payload, isEmpty);
    expect(reveal.snapshot.entry, isEmpty);
  });

  for (final cause in ['lock', 'revision', 'domain', 'removed']) {
    test(
      '$cause during selected reveal prevents completion and clears body',
      () async {
        final selected = (await candidates()).first;
        final pending = Completer<LocalCurrentEntryReveal>();
        when(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) => pending.future);
        var completed = false;
        final operation = source.withCredential(
          candidate: selected,
          selectedHost: 'login.example.com',
          memberPrivateKey: Uint8List(32),
          validateRequest: guard,
          complete: (_) async {
            completed = true;
          },
        );
        final rejected = expectLater(
          operation,
          cause == 'lock'
              ? throwsStateError
              : throwsA(isA<AutoFillCredentialException>()),
        );
        switch (cause) {
          case 'lock':
            authorized = false;
          case 'revision':
            index.values = [syntheticAutoFillEntry('chosen', revision: '2')];
          case 'domain':
            index.values = [
              syntheticAutoFillEntry('chosen', domain: 'other.example.com'),
            ];
          case 'removed':
            index.values = [];
        }
        final reveal = syntheticAutoFillReveal();
        pending.complete(reveal);
        await rejected;
        expect(completed, isFalse);
        expect(reveal.snapshot.payload, isEmpty);
      },
    );
  }
}
