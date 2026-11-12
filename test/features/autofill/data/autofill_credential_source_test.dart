import '../support/credential_source_fixture.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_username_previews.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

  for (final change in ['lease', 'entry', 'request']) {
    test(
      'memoized username revalidates $change without reopening a body',
      () async {
        var now = DateTime.utc(2026, 1, 1, 12);
        source = AutoFillCredentialSource(
          memberIndex: index,
          localEntries: entries,
          now: () => now,
        );
        final candidate = (await candidates()).first;
        final reveal = syntheticAutoFillReveal(
          issuedAt: now,
          notAfter: now.add(const Duration(minutes: 5)),
        );
        when(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => reveal);
        final memo = AutoFillUsernamePreviews();
        var loads = 0;
        Future<AutoFillUsernamePreview> load() {
          loads++;
          return source.readUsernamePreview(
            candidate: candidate,
            selectedHost: 'login.example.com',
            memberPrivateKey: Uint8List(32),
            validateRequest: guard,
          );
        }

        expect(await memo.read('chosen:1:1', load), 'synthetic-user');
        expect(reveal.snapshot.payload, isEmpty);
        if (change == 'lease') now = now.add(const Duration(minutes: 5));
        if (change == 'entry') index.values = [];
        if (change == 'request') authorized = false;
        await expectLater(
          memo.read('chosen:1:1', load),
          throwsA(anyOf(isA<AutoFillCredentialException>(), isA<StateError>())),
        );
        expect(
          loads,
          1,
          reason: 'Rejected cached metadata must not reopen the secret',
        );
        memo.clear();
      },
    );
  }

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
    'same-host accounts keep their own usernames without opening secrets',
    () async {
      index.values = [
        syntheticAutoFillEntry('first', username: 'first@example.test'),
        syntheticAutoFillEntry('second', username: 'second@example.test'),
      ];
      final rows = await candidates();
      expect(rows.map((row) => row.username), [
        'first@example.test',
        'second@example.test',
      ]);
      expect(rows.map((row) => row.entryId), ['first', 'second']);
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

  test(
    'legacy username preview clears body and cannot return after lock',
    () async {
      final selected = (await candidates()).first;
      final reveal = syntheticAutoFillReveal();
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => reveal);
      expect(
        await source.readUsernamePreview(
          candidate: selected,
          selectedHost: 'login.example.com',
          memberPrivateKey: Uint8List(32),
          validateRequest: guard,
        ),
        isA<AutoFillUsernamePreview>().having(
          (preview) => preview.username,
          'username',
          'synthetic-user',
        ),
      );
      expect(reveal.snapshot.payload, isEmpty);
      final revoked = syntheticAutoFillReveal();
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {
        authorized = false;
        return revoked;
      });
      await expectLater(
        source.readUsernamePreview(
          candidate: selected,
          selectedHost: 'login.example.com',
          memberPrivateKey: Uint8List(32),
          validateRequest: guard,
        ),
        throwsStateError,
      );
      expect(revoked.snapshot.payload, isEmpty);
    },
  );

  for (final password in ['', ' ']) {
    test(
      'handoff rejects empty passwords without trimming valid passwords: ${password.isEmpty}',
      () async {
        final selected = (await candidates()).first;
        final reveal = syntheticAutoFillReveal();
        reveal.snapshot.payload['password'] = password;
        when(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => reveal);
        var completed = false;
        final operation = source.withCredential(
          candidate: selected,
          selectedHost: 'login.example.com',
          memberPrivateKey: Uint8List(32),
          validateRequest: guard,
          complete: (value) async {
            completed = true;
            expect(value.password, password);
          },
        );
        if (password.isEmpty) {
          await expectLater(
            operation,
            throwsA(isA<AutoFillCredentialException>()),
          );
          expect(completed, isFalse);
        } else {
          await operation;
          expect(completed, isTrue);
        }
        expect(reveal.snapshot.payload, isEmpty);
        expect(reveal.snapshot.secret, isEmpty);
        verify(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).called(1);
        verifyNoMoreInteractions(entries);
      },
    );
  }

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

  test(
    'binding diagnostic contains only boolean outcomes, never credential values',
    () async {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = previous);
      final selected = (await candidates()).first;
      final reveal = syntheticAutoFillReveal();
      reveal.snapshot.entry['vaultId'] = 'SENSITIVE_VAULT';
      reveal.snapshot.payload['username'] = 'SENSITIVE_USERNAME';
      reveal.snapshot.payload['password'] = 'SENSITIVE_PASSWORD';
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
            fail('Must not hand off');
          },
        ),
        throwsA(isA<AutoFillCredentialException>()),
      );
      expect(lines, [
        'AUTOFILL_CREDENTIAL BINDING entry=true vault=false contextVault=true organization=true revision=true keyVersion=true active=true usernameString=true passwordString=true',
      ]);
      expect(lines.join(), isNot(contains('SENSITIVE')));
    },
  );

  test(
    'canonical lease issued slightly ahead fills on first selection',
    () async {
      final now = DateTime.utc(2030);
      source = AutoFillCredentialSource(
        memberIndex: index,
        localEntries: entries,
        now: () => now,
      );
      final selected = (await candidates()).first;
      final reveal = syntheticAutoFillReveal(
        issuedAt: now.add(const Duration(seconds: 3)),
        notAfter: now.add(const Duration(hours: 24, seconds: 3)),
      );
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => reveal);
      var fills = 0;
      await source.withCredential(
        candidate: selected,
        selectedHost: 'login.example.com',
        memberPrivateKey: Uint8List(32),
        validateRequest: guard,
        complete: (value) async {
          expect(value.password, 'synthetic-password');
          fills++;
        },
      );
      expect(fills, 1);
    },
  );

  for (final scenario in [
    'boundary',
    'future',
    'expired',
    'rollback',
    'expires-during-fill',
  ]) {
    test('lease time boundary remains enforced: $scenario', () async {
      final baseline = DateTime.utc(2030);
      var now = baseline;
      source = AutoFillCredentialSource(
        memberIndex: index,
        localEntries: entries,
        now: () => now,
      );
      final selected = (await candidates()).first;
      final issuedAt = scenario == 'boundary'
          ? baseline.add(const Duration(minutes: 5))
          : scenario == 'future'
          ? baseline.add(const Duration(minutes: 5, milliseconds: 1))
          : baseline;
      final notAfter = scenario == 'expired'
          ? baseline
          : issuedAt.add(const Duration(hours: 24));
      final reveal = syntheticAutoFillReveal(
        issuedAt: issuedAt,
        notAfter: notAfter,
      );
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => reveal);
      var reads = 0;
      final filling = source.withCredential(
        candidate: selected,
        selectedHost: 'login.example.com',
        memberPrivateKey: Uint8List(32),
        validateRequest: guard,
        complete: (value) async {
          if (scenario == 'rollback') {
            now = baseline.subtract(const Duration(minutes: 6));
          }
          if (scenario == 'expires-during-fill') now = notAfter;
          expect(value.password, 'synthetic-password');
          reads++;
        },
      );
      if (scenario == 'boundary') {
        await filling;
        expect(reads, 1);
      } else {
        await expectLater(
          filling,
          throwsA(
            isA<AutoFillCredentialException>().having(
              (error) => error.kind,
              'kind',
              AutoFillCredentialFailure.expired,
            ),
          ),
        );
        expect(reads, 0);
      }
      expect(reveal.snapshot.payload, isEmpty);
    });
  }

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
