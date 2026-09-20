import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_lifetime.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_reception.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_reception_cubit.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Remote extends Mock implements EntryShareRecipientDatasource {}

const EntryShareRecipientOwner _guest = (
  principalId: null,
  organizationId: null,
  authorizationGeneration: null,
  keyGeneration: 0,
);
final _fixture =
    jsonDecode(
          File('test/fixtures/crypto/entry-share-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
final _shareId = _fixture['scope']['shareId'] as String;
final _initialTime = DateTime.utc(2026, 9, 20, 12);

EntryShareDelivery _delivery({String? shareId}) {
  final scope = _fixture['scope'];
  return EntryShareDelivery(
    authority: EntryShareScope(
      shareId: shareId ?? scope['shareId'],
      organizationId: scope['organizationId'],
      vaultId: scope['vaultId'],
      entryId: scope['entryId'],
      sourceRevision: scope['sourceRevision'],
      expiresAt: scope['expiresAt'],
    ),
    packet: EntryShareCiphertext(
      nonce: _fixture['nonce'],
      ciphertext: _fixture['ciphertext'],
    ),
  );
}

void main() {
  late SodiumSumo sodium;
  late _Remote remote;
  late EntryShareReceptionCubit cubit;
  late EntryShareSecrets secrets;
  late EntryShareRecipientOwner? owner;
  late EntryShareRecipientSession session;
  late DateTime now;
  late Duration elapsed;
  late Future<SodiumSumo> Function() sodiumLoader;
  late Future<EntryShareRecipientOwner?> Function() ownerReader;

  setUpAll(() async {
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      const EntryShareRecipientSession(
        sessionId: '',
        sessionToken: '',
        expiresAt: '',
        recipientMode: '',
        protection: '',
      ),
    );
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = configured != null || Platform.isLinux
        ? await sodium_ffi.SodiumSumoInit.init(
            () => DynamicLibrary.open(configured ?? 'libsodium.so'),
          )
        : await SodiumSumoInit.init();
  });

  EntryShareRecipientSession makeSession({
    String mode = 'anyoneWithLink',
    String protection = 'none',
    String? expiry,
  }) => EntryShareRecipientSession(
    sessionId: 'synthetic-session',
    sessionToken: 'synthetic-token',
    expiresAt:
        expiry ??
        _initialTime.add(const Duration(minutes: 10)).toIso8601String(),
    recipientMode: mode,
    protection: protection,
  );

  EntryShareReceptionCubit makeCubit({EntryShareLifetime? lifetime}) =>
      EntryShareReceptionCubit(
        remote: remote,
        crypto: EntryShareCryptoService(sodiumLoader: () => sodiumLoader()),
        shareId: _shareId,
        secrets: secrets,
        owner: _guest,
        ownerReader: () => ownerReader(),
        now: () => now,
        elapsed: () => elapsed,
        lifetime: lifetime,
      );

  setUp(() {
    remote = _Remote();
    owner = _guest;
    ownerReader = () async => owner;
    now = _initialTime;
    elapsed = Duration.zero;
    sodiumLoader = () async => sodium;
    secrets = EntryShareSecrets(
      key: VaultProtocolBytes.hex(_fixture['keyHex']),
      accessToken: Uint8List(32)..fillRange(0, 32, 7),
    );
    session = makeSession();
    when(
      () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async => session);
    when(
      () => remote.requestOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        language: any(named: 'language'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.verifyOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        code: any(named: 'code'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.verifySecret(
        any(),
        any(),
        secret: any(named: 'secret'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async => _delivery());
    when(
      () => remote.confirmDisplay(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async {});
    cubit = makeCubit();
  });
  tearDown(() async => cubit.close());

  test(
    'ingress deadline survives mounting and a longer remote session',
    () async {
      await cubit.close();
      secrets = EntryShareSecrets(
        key: Uint8List(32)..fillRange(0, 32, 7),
        accessToken: Uint8List(32)..fillRange(0, 32, 8),
      );
      final lifetime = EntryShareLifetime(
        now: () => now,
        elapsed: () => elapsed,
      );
      elapsed = const Duration(minutes: 14);
      cubit = makeCubit(lifetime: lifetime);
      expect(await cubit.open(), EntryShareReceptionOutcome.completed);
      elapsed = const Duration(minutes: 15);
      expect(await cubit.revalidate(), false);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      expect(secrets.key, everyElement(0));
      expect(secrets.accessToken, everyElement(0));
    },
  );

  test(
    'expired ingress capability is wiped before any recipient request',
    () async {
      await cubit.close();
      secrets = EntryShareSecrets(
        key: Uint8List(32)..fillRange(0, 32, 7),
        accessToken: Uint8List(32)..fillRange(0, 32, 8),
      );
      final lifetime = EntryShareLifetime(
        now: () => now,
        elapsed: () => elapsed,
      );
      elapsed = const Duration(minutes: 15);
      cubit = makeCubit(lifetime: lifetime);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      expect(await cubit.open(), EntryShareReceptionOutcome.ignored);
      verifyNever(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      );
      expect(secrets.key, everyElement(0));
      expect(secrets.accessToken, everyElement(0));
    },
  );

  test(
    'guest explicitly opens, decrypts native fixture, then separately confirms display',
    () async {
      verifyZeroInteractions(remote);
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.open(), EntryShareReceptionOutcome.completed);
      expect(cubit.state.phase, EntryShareReceptionPhase.verification);
      expect(cubit.state.gatesReady, true);
      expect(await cubit.receive(), EntryShareReceptionOutcome.completed);
      expect(cubit.state.snapshot!.toJson(), _fixture['snapshot']);
      verifyNever(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      await cubit.confirmDisplay();
      expect(cubit.state.confirmation, EntryShareConfirmation.confirmed);
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.confirmDisplay(), EntryShareReceptionOutcome.ignored);
      verify(
        () => remote.receive(
          _shareId,
          session,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  test(
    'OTP and optional PIN are both required before delivery or end',
    () async {
      session = makeSession(mode: 'namedRecipient', protection: 'pin');
      await cubit.open();
      expect(
        await cubit.verifyOtp('012345'),
        EntryShareReceptionOutcome.ignored,
      );
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.end(), EntryShareReceptionOutcome.ignored);
      await cubit.verifySecret('001234');
      expect(cubit.state.gatesReady, false);
      await cubit.requestOtp('pl');
      await cubit.verifyOtp('012345');
      expect(cubit.state.gatesReady, true);
      await cubit.receive();
      verify(
        () => remote.verifySecret(
          _shareId,
          session,
          secret: '001234',
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verify(
        () => remote.verifyOtp(
          _shareId,
          session,
          generation: 1,
          code: '012345',
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  test(
    'ambiguous OTP send retries same generation and blocks stale code',
    () async {
      session = makeSession(mode: 'namedRecipient');
      final generations = <int>[];
      when(
        () => remote.requestOtp(
          any(),
          any(),
          generation: any(named: 'generation'),
          language: any(named: 'language'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((call) async {
        generations.add(call.namedArguments[#generation] as int);
        if (generations.length == 1) {
          throw const EntryShareRecipientRequestException();
        }
      });
      await cubit.open();
      expect(await cubit.requestOtp('pl'), EntryShareReceptionOutcome.failed);
      expect(cubit.state.otpRetry, true);
      expect(
        await cubit.verifyOtp('012345'),
        EntryShareReceptionOutcome.ignored,
      );
      await cubit.requestOtp('pl');
      expect(cubit.state.otpRequested, true);
      expect(cubit.state.otpRetry, false);
      await cubit.requestOtp('pl');
      expect(generations, [1, 1, 2]);
    },
  );

  test('failed proof does not unlock client gates', () async {
    session = makeSession(mode: 'namedRecipient', protection: 'password');
    when(
      () => remote.verifySecret(
        any(),
        any(),
        secret: any(named: 'secret'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(const EntryShareRecipientRequestException());
    when(
      () => remote.verifyOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        code: any(named: 'code'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(const EntryShareRecipientRequestException());
    await cubit.open();
    await cubit.requestOtp('en');
    expect(
      await cubit.verifySecret(' exact secret '),
      EntryShareReceptionOutcome.failed,
    );
    expect(await cubit.verifyOtp('999999'), EntryShareReceptionOutcome.failed);
    expect(cubit.state.emailVerified, false);
    expect(cubit.state.secretVerified, false);
    expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
  });

  test(
    'ambiguous delivery retries same session, never opens another receipt',
    () async {
      final sessions = <EntryShareRecipientSession>[];
      when(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((call) async {
        sessions.add(call.positionalArguments[1] as EntryShareRecipientSession);
        if (sessions.length == 1) {
          throw const EntryShareRecipientRequestException();
        }
        return _delivery();
      });
      await cubit.open();
      expect(await cubit.receive(), EntryShareReceptionOutcome.failed);
      expect(await cubit.receive(), EntryShareReceptionOutcome.completed);
      expect(sessions.length, 2);
      expect(identical(sessions.first, sessions.last), true);
      verify(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).called(1);
    },
  );

  test(
    'failed confirmation retains decrypted copy and only retries confirmation',
    () async {
      var confirmations = 0;
      when(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        if (++confirmations == 1) {
          throw const EntryShareRecipientRequestException();
        }
      });
      await cubit.open();
      await cubit.receive();
      final snapshot = cubit.state.snapshot;
      expect(await cubit.confirmDisplay(), EntryShareReceptionOutcome.failed);
      expect(cubit.state.confirmation, EntryShareConfirmation.failed);
      expect(identical(cubit.state.snapshot, snapshot), true);
      await cubit.confirmDisplay();
      expect(cubit.state.confirmation, EntryShareConfirmation.confirmed);
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  test(
    'ending drops plaintext and wipes keys; failure can retry without redelivery',
    () async {
      var ends = 0;
      when(
        () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) async {
        if (++ends == 1) throw const EntryShareRecipientRequestException();
      });
      await cubit.open();
      await cubit.receive();
      expect(await cubit.end(), EntryShareReceptionOutcome.failed);
      expect(cubit.state.snapshot, isNotNull);
      expect(await cubit.end(), EntryShareReceptionOutcome.completed);
      expect(cubit.state.phase, EntryShareReceptionPhase.ended);
      expect(cubit.state.snapshot, isNull);
      expect(secrets.key, everyElement(0));
      expect(secrets.accessToken, everyElement(0));
      expect(await cubit.open(), EntryShareReceptionOutcome.ignored);
    },
  );

  test(
    'unknown server gates remain readable but cannot enable delivery',
    () async {
      session = makeSession(mode: 'future', protection: 'future');
      await cubit.open();
      expect(cubit.state.recipientMode, 'future');
      expect(cubit.state.protection, 'future');
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
    },
  );

  test(
    'source substitution never exposes plaintext or confirms a display',
    () async {
      when(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => _delivery(shareId: '11112233-4455-4677-8899-aabbccddeeff'),
      );
      await cubit.open();
      expect(await cubit.receive(), EntryShareReceptionOutcome.cancelled);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      expect(cubit.state.snapshot, isNull);
      expect(secrets.key, everyElement(0));
      verifyNever(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    },
  );

  for (final fail in [false, true]) {
    test(
      'late session ${fail ? 'error' : 'success'} after ownership change cannot restore state',
      () async {
        final deferred = Completer<EntryShareRecipientSession>();
        when(
          () =>
              remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
        ).thenAnswer((_) => deferred.future);
        final opening = cubit.open();
        await Future<void>.delayed(Duration.zero);
        owner = (
          principalId: 'replacement',
          organizationId: 'org',
          authorizationGeneration: '1',
          keyGeneration: 1,
        );
        if (fail) {
          deferred.completeError(const EntryShareRecipientRequestException());
        } else {
          deferred.complete(session);
        }
        expect(await opening, EntryShareReceptionOutcome.cancelled);
        expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
        expect(secrets.key, everyElement(0));
      },
    );
  }

  for (final action in ['delivery', 'confirmation', 'end']) {
    for (final fails in [false, true]) {
      test(
        'late $action ${fails ? 'error' : 'success'} after key replacement is discarded',
        () async {
          final deferred = Completer<void>();
          await cubit.open();
          if (action == 'confirmation') await cubit.receive();
          Future<EntryShareReceptionOutcome> Function() operation;
          if (action == 'delivery') {
            when(
              () => remote.receive(
                any(),
                any(),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).thenAnswer((_) async {
              await deferred.future;
              return _delivery();
            });
            operation = cubit.receive;
          } else if (action == 'confirmation') {
            when(
              () => remote.confirmDisplay(
                any(),
                any(),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).thenAnswer((_) => deferred.future);
            operation = cubit.confirmDisplay;
          } else {
            when(
              () => remote.end(
                any(),
                any(),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).thenAnswer((_) => deferred.future);
            operation = cubit.end;
          }
          final result = operation();
          await Future<void>.delayed(Duration.zero);
          owner = (
            principalId: null,
            organizationId: null,
            authorizationGeneration: null,
            keyGeneration: 1,
          );
          if (fails) {
            deferred.completeError(const EntryShareRecipientRequestException());
          } else {
            deferred.complete();
          }
          expect(await result, EntryShareReceptionOutcome.cancelled);
          expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
          expect(cubit.state.snapshot, isNull);
          expect(secrets.key, everyElement(0));
        },
      );
    }
  }

  test('clear cancels pending delivery and discards late plaintext', () async {
    final deferred = Completer<EntryShareDelivery>();
    CancelToken? token;
    when(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((call) {
      token = call.namedArguments[#cancelToken] as CancelToken;
      return deferred.future;
    });
    await cubit.open();
    final receiving = cubit.receive();
    await Future<void>.delayed(Duration.zero);
    cubit.clear();
    expect(token!.isCancelled, true);
    deferred.complete(_delivery());
    expect(await receiving, EntryShareReceptionOutcome.cancelled);
    expect(cubit.state.snapshot, isNull);
  });

  test('late native crypto after clear cannot publish or confirm', () async {
    final deferred = Completer<SodiumSumo>();
    final reached = Completer<void>();
    sodiumLoader = () {
      reached.complete();
      return deferred.future;
    };
    await cubit.open();
    final receiving = cubit.receive();
    await reached.future;
    cubit.clear();
    deferred.complete(sodium);
    expect(await receiving, EntryShareReceptionOutcome.cancelled);
    expect(cubit.state.snapshot, isNull);
    expect(secrets.key, everyElement(0));
  });

  test(
    'repeated taps never create concurrent sessions or deliveries',
    () async {
      final deferred = Completer<EntryShareRecipientSession>();
      when(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) => deferred.future);
      final opening = cubit.open();
      expect(await cubit.open(), EntryShareReceptionOutcome.ignored);
      deferred.complete(session);
      await opening;
      final first = cubit.receive();
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
      await first;
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  test(
    'wall expiry checked before an action even when timers have not fired',
    () async {
      await cubit.open();
      now = _initialTime.add(const Duration(minutes: 11));
      expect(await cubit.receive(), EntryShareReceptionOutcome.cancelled);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      verifyNever(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    },
  );

  test('clock rollback cannot extend the monotonic deadline', () async {
    await cubit.open();
    now = _initialTime.subtract(const Duration(hours: 1));
    elapsed = const Duration(minutes: 11);
    expect(await cubit.revalidate(), false);
    expect(secrets.key, everyElement(0));
  });

  test(
    'unopened capability expires after 15 minutes and cannot be resurrected',
    () async {
      await cubit.close();
      secrets = EntryShareSecrets(
        key: Uint8List(32)..fillRange(0, 32, 7),
        accessToken: Uint8List(32)..fillRange(0, 32, 8),
      );
      fakeAsync((clock) {
        cubit = makeCubit();
        clock.elapse(const Duration(minutes: 15));
        expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
        expect(secrets.key, everyElement(0));
        expect(secrets.accessToken, everyElement(0));
      });
    },
  );

  test(
    'invalid expiry fails closed as a local capability lifetime boundary',
    () async {
      session = makeSession(expiry: 'not-a-date');
      expect(await cubit.open(), EntryShareReceptionOutcome.cancelled);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    },
  );

  test(
    'email suspension blocks all proof and delivery operations until resume',
    () async {
      session = makeSession(mode: 'namedRecipient', protection: 'pin');
      await cubit.open();
      await cubit.requestOtp('en');
      expect(cubit.suspendForEmail(), true);
      expect(cubit.state.snapshot, isNull);
      clearInteractions(remote);
      expect(await cubit.open(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.requestOtp('en'), EntryShareReceptionOutcome.ignored);
      expect(
        await cubit.verifyOtp('012345'),
        EntryShareReceptionOutcome.ignored,
      );
      expect(
        await cubit.verifySecret('001234'),
        EntryShareReceptionOutcome.ignored,
      );
      expect(await cubit.receive(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.confirmDisplay(), EntryShareReceptionOutcome.ignored);
      expect(await cubit.end(), EntryShareReceptionOutcome.ignored);
      verifyZeroInteractions(remote);
      await cubit.resumeFromEmail();
      expect(cubit.state.suspended, false);
      await cubit.verifyOtp('012345');
      verify(
        () => remote.verifyOtp(
          _shareId,
          session,
          generation: 1,
          code: '012345',
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );

  for (final monotonic in [false, true]) {
    test(
      'email resume never extends original expiry: monotonic=$monotonic',
      () async {
        session = makeSession(mode: 'namedRecipient');
        await cubit.open();
        await cubit.requestOtp('en');
        expect(cubit.suspendForEmail(), true);
        if (monotonic) {
          now = _initialTime.subtract(const Duration(hours: 1));
          elapsed = const Duration(minutes: 10);
        } else {
          now = _initialTime.add(const Duration(minutes: 10));
        }
        await cubit.resumeFromEmail();
        expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
        expect(secrets.key, everyElement(0));
        expect(secrets.accessToken, everyElement(0));
        expect(
          await cubit.verifyOtp('012345'),
          EntryShareReceptionOutcome.ignored,
        );
      },
    );
  }

  test(
    'changed owner on email resume destroys the pending capability',
    () async {
      session = makeSession(mode: 'namedRecipient');
      await cubit.open();
      await cubit.requestOtp('en');
      expect(cubit.suspendForEmail(), true);
      owner = null;
      await cubit.resumeFromEmail();
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      expect(secrets.key, everyElement(0));
    },
  );

  test(
    'late foreground validation cannot resume after another background transition',
    () async {
      session = makeSession(mode: 'namedRecipient');
      await cubit.open();
      await cubit.requestOtp('en');
      expect(cubit.suspendForEmail(), true);
      final pending = Completer<EntryShareRecipientOwner?>();
      ownerReader = () => pending.future;
      final resuming = cubit.resumeFromEmail();
      expect(cubit.suspendForEmail(), true);
      pending.complete(_guest);
      await resuming;
      expect(cubit.state.suspended, true);
      ownerReader = () async => owner;
      await cubit.resumeFromEmail();
      expect(cubit.state.suspended, false);
    },
  );

  test(
    'only idle, requested, unverified named-email proof may suspend',
    () async {
      expect(cubit.suspendForEmail(), false);
      session = makeSession(mode: 'namedRecipient');
      await cubit.open();
      expect(cubit.suspendForEmail(), false);
      final pending = Completer<void>();
      when(
        () => remote.requestOtp(
          any(),
          any(),
          generation: any(named: 'generation'),
          language: any(named: 'language'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => pending.future);
      final sending = cubit.requestOtp('en');
      expect(cubit.suspendForEmail(), false);
      pending.complete();
      await sending;
      await cubit.verifyOtp('012345');
      expect(cubit.suspendForEmail(), false);
      await cubit.receive();
      expect(cubit.suspendForEmail(), false);
    },
  );

  test('anyone link cannot retain a capability for an email detour', () async {
    await cubit.open();
    expect(cubit.suspendForEmail(), false);
    expect(cubit.state.suspended, false);
  });
}
