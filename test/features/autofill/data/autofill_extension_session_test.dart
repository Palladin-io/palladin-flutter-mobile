import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_credential_source.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_extension_session.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';

import '../support/credential_source_fixture.dart';

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(32)));
  late TestAutoFillEntries entries;
  late TestAutoFillIndex index;
  late AutoFillExtensionSession session;
  var current = true;
  var closed = 0;
  var completions = 0;
  Future<void> Function()? validation;
  Future<void> Function()? beforeCompletion;

  setUp(() {
    current = true;
    closed = 0;
    completions = 0;
    validation = null;
    beforeCompletion = null;
    index = TestAutoFillIndex()
      ..values = [
        syntheticAutoFillEntry('chosen'),
        syntheticAutoFillEntry('other'),
      ];
    entries = TestAutoFillEntries();
    session = AutoFillExtensionSession(
      request: AutoFillRequest.parse({
        'id': 'request',
        'remainingMs': 60000,
        'mode': 'WEB',
        'verifiedHosts': ['login.example.com'],
        'usernameOnly': false,
      }),
      source: AutoFillCredentialSource(
        memberIndex: index,
        localEntries: entries,
      ),
      vaultIds: ['vault'],
      memberPrivateKey: Uint8List.fromList(List.filled(32, 7)),
      validateNative: () async {
        await validation?.call();
        return current;
      },
      completeNative: (value) async {
        await beforeCompletion?.call();
        expect(value['username'], 'synthetic-user');
        completions++;
      },
      clearRuntime: () {
        closed++;
      },
    );
  });
  tearDown(() => session.close());

  test(
    'native chooser gets only index metadata, selection alone opens a body once',
    () async {
      final choices = await session.candidates();
      expect(choices.map((row) => row['label']), ['chosen', 'other']);
      expect(choices.first.keys.toSet(), {'selectionId', 'label', 'domains'});
      verifyZeroInteractions(entries);
      final revealed = syntheticAutoFillReveal();
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async => revealed);
      await session.select(
        selectionId: choices.first['selectionId'] as String,
        selectedHost: 'login.example.com',
        manualConfirmed: false,
      );
      expect(completions, 1);
      expect(revealed.snapshot.payload, isEmpty);
      expect(closed, 1);
      await expectLater(
        session.select(
          selectionId: choices.first['selectionId'] as String,
          selectedHost: 'login.example.com',
          manualConfirmed: false,
        ),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      expect(completions, 1);
    },
  );

  test(
    'native source changes during metadata validation expose no rows',
    () async {
      validation = () async {
        current = false;
      };
      await expectLater(
        session.candidates(),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      verifyZeroInteractions(entries);
      expect(closed, 1);
    },
  );

  test(
    'cancel during selected reveal clears key and prevents native completion',
    () async {
      final choices = await session.candidates();
      final pending = Completer<void>();
      Uint8List? borrowed;
      final reveal = syntheticAutoFillReveal();
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((call) async {
        borrowed = call.namedArguments[#memberPrivateKey] as Uint8List;
        await pending.future;
        return reveal;
      });
      final selecting = session.select(
        selectionId: choices.first['selectionId'] as String,
        selectedHost: 'login.example.com',
        manualConfirmed: false,
      );
      final rejected = expectLater(
        selecting,
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      await Future<void>.delayed(Duration.zero);
      session.close();
      expect(borrowed, everyElement(0));
      pending.complete();
      await rejected;
      expect(completions, 0);
      expect(reveal.snapshot.payload, isEmpty);
    },
  );

  for (final invalidToken in [true, false]) {
    test(
      invalidToken
          ? 'foreign selection token cannot open a secret'
          : 'different exact host cannot open a secret',
      () async {
        final choices = await session.candidates();
        await expectLater(
          session.select(
            selectionId: invalidToken
                ? 'foreign'
                : choices.first['selectionId'] as String,
            selectedHost: invalidToken
                ? 'login.example.com'
                : 'other.example.com',
            manualConfirmed: false,
          ),
          throwsA(isA<AutoFillRequestInvalidated>()),
        );
        verifyZeroInteractions(entries);
        expect(completions, 0);
      },
    );
  }
  test(
    'revocation after selected decrypt prevents OS handoff and clears plaintext',
    () async {
      final choices = await session.candidates();
      final reveal = syntheticAutoFillReveal();
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: 'chosen',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {
        current = false;
        return reveal;
      });
      await expectLater(
        session.select(
          selectionId: choices.first['selectionId'] as String,
          selectedHost: 'login.example.com',
          manualConfirmed: false,
        ),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      expect(completions, 0);
      expect(reveal.snapshot.payload, isEmpty);
    },
  );
  test('missing explicit manual consent cannot open a selected body', () async {
    session.close();
    session = AutoFillExtensionSession(
      request: AutoFillRequest.parse({
        'id': 'manual',
        'remainingMs': 60000,
        'mode': 'MANUAL_NATIVE',
        'verifiedHosts': [],
        'usernameOnly': false,
      }),
      source: AutoFillCredentialSource(
        memberIndex: index,
        localEntries: entries,
      ),
      vaultIds: ['vault'],
      memberPrivateKey: Uint8List(32),
      validateNative: () async => true,
      completeNative: (_) async {
        completions++;
      },
      clearRuntime: () {},
    );
    final choices = await session.candidates();
    await expectLater(
      session.select(
        selectionId: choices.first['selectionId'] as String,
        selectedHost: 'login.example.com',
        manualConfirmed: false,
      ),
      throwsA(isA<AutoFillRequestInvalidated>()),
    );
    verifyZeroInteractions(entries);
    expect(completions, 0);
  });
}
