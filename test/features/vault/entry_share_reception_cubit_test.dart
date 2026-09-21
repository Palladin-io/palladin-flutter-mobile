import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_account_continuation.dart';
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

class _Auth extends Mock implements AuthBloc {}

const EntryShareRecipientOwner _guest = (
  principalId: null,
  organizationId: null,
  authorizationGeneration: null,
  keyGeneration: 0,
);
const EntryShareRecipientOwner _account = (
  principalId: 'recipient',
  organizationId: 'recipient-organization',
  authorizationGeneration: '7',
  keyGeneration: 1,
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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
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

  group('account continuation coordinator', () {
    late _Auth auth;
    late AuthState authState;
    late StreamController<AuthState> authEvents;
    late EntryShareIngress ingress;
    late EntryShareAccountContinuation continuation;
    late Future<EntryShareRecipientOwner?> Function(String?) readAuthority;

    Future<void> changeAuth(AuthState value) async {
      authState = value;
      authEvents.add(value);
      await Future<void>.delayed(Duration.zero);
    }

    AuthAuthenticated readyAccount() => AuthAuthenticated(
      userId: _account.principalId!,
      isOnboarded: true,
      emailVerified: true,
      isVaultLocked: false,
      privateKey: Uint8List(32),
    );

    setUp(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      auth = _Auth();
      authState = const AuthUnauthenticated();
      authEvents = StreamController<AuthState>.broadcast(sync: true);
      when(() => auth.state).thenAnswer((_) => authState);
      when(() => auth.stream).thenAnswer((_) => authEvents.stream);
      ingress = EntryShareIngress(
        links: EntryShareLinkService(
          EnvConfig.local(sharingWebOrigin: 'http://localhost'),
        ),
      );
      readAuthority = (_) async => owner;
      continuation = EntryShareAccountContinuation(
        auth: auth,
        ingress: ingress,
        ownerReader: (principal) => readAuthority(principal),
      );
    });

    tearDown(() async {
      continuation.dispose();
      ingress.dispose();
      await authEvents.close();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    test(
      'guest login returns the same received copy without a second delivery or ACK',
      () async {
        await cubit.open();
        await cubit.receive();
        await cubit.confirmDisplay();
        final snapshot = cubit.state.snapshot;
        final lifetime = cubit.lifetime;
        expect(
          await continuation.begin(cubit, EntryShareAccountAction.login),
          true,
        );
        expect(continuation.accountRoute, '/login');
        continuation.guardRoute(Uri.parse('/login'));
        await cubit.close();
        owner = _account;
        await changeAuth(readyAccount());
        expect(continuation.ready, true);
        final resumed = await continuation.take(
          version: ingress.version,
          owner: _account,
          ownerReader: () async => owner,
        );
        expect(resumed, isNotNull);
        addTearDown(resumed!.close);
        expect(resumed.state.snapshot, same(snapshot));
        expect(resumed.lifetime, same(lifetime));
        expect(resumed.state.confirmation, EntryShareConfirmation.confirmed);
        expect(continuation.active, false);
        verify(
          () => remote.receive(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        verify(
          () => remote.confirmDisplay(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      },
    );

    test(
      'guest can retry cancelled login without opening a receiver session',
      () async {
        expect(
          await continuation.begin(cubit, EntryShareAccountAction.register),
          true,
        );
        expect(continuation.accountRoute, '/register');
        continuation.guardRoute(Uri.parse('/register'));
        await changeAuth(const AuthLoading());
        await changeAuth(AuthError(StateError('synthetic failure')));
        await changeAuth(const AuthUnauthenticated());
        expect(continuation.active, true);
        expect(continuation.ready, false);
        expect(continuation.guardRoute(Uri.parse('/share')), '/register');
        verifyNever(
          () =>
              remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
        );
      },
    );

    test(
      'registration, verification and unlock must all finish before claim',
      () async {
        await continuation.begin(cubit, EntryShareAccountAction.register);
        continuation.guardRoute(Uri.parse('/register'));
        owner = _account;
        const initial = AuthAuthenticated(
          userId: 'recipient',
          isOnboarded: false,
          emailVerified: false,
        );
        await changeAuth(initial);
        expect(continuation.accountRoute, '/onboarding');
        expect(continuation.ready, false);
        await changeAuth(initial.copyWith(isOnboarded: true));
        expect(continuation.accountRoute, '/verify-email');
        expect(continuation.ready, false);
        await changeAuth(
          initial.copyWith(isOnboarded: true, emailVerified: true),
        );
        expect(continuation.accountRoute, '/unlock');
        expect(continuation.ready, false);
        await changeAuth(readyAccount());
        expect(continuation.ready, true);
      },
    );

    test(
      'repeated auth observations preserve a pending authorized unlock',
      () async {
        await continuation.begin(cubit, EntryShareAccountAction.login);
        continuation.guardRoute(Uri.parse('/login'));
        owner = (
          principalId: _account.principalId,
          organizationId: _account.organizationId,
          authorizationGeneration: '7',
          keyGeneration: 0,
        );
        await changeAuth(
          const AuthAuthenticated(userId: 'recipient', isOnboarded: true),
        );
        final pending = Completer<EntryShareRecipientOwner?>();
        readAuthority = (_) => pending.future;
        final unlocked = readyAccount();
        await changeAuth(unlocked);
        await changeAuth(unlocked.copyWith());
        owner = _account;
        pending.complete(owner);
        await Future<void>.delayed(Duration.zero);
        expect(continuation.active, true);
        expect(continuation.ready, true);
      },
    );

    for (final route in [
      '/recovery',
      '/',
      '/login?redirect=/share',
      '/share#secret',
      '/verify-email?unexpected=value',
    ]) {
      test(
        'unrelated or secret-bearing route discards transfer: $route',
        () async {
          await continuation.begin(cubit, EntryShareAccountAction.login);
          continuation.guardRoute(Uri.parse(route));
          expect(continuation.active, false);
          expect(secrets.key, everyElement(0));
          verify(() => remote.close()).called(1);
        },
      );
    }

    test(
      'email/OAuth app detour retains only the explicitly transferred flow',
      () async {
        await cubit.open();
        await cubit.receive();
        await continuation.begin(cubit, EntryShareAccountAction.login);
        continuation.guardRoute(Uri.parse('/login'));
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(continuation.active, true);
        owner = _account;
        await changeAuth(readyAccount());
        expect(continuation.ready, false);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(continuation.ready, true);
        continuation.guardRoute(Uri.parse('/share'));
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(continuation.active, false);
        expect(secrets.key, everyElement(0));
      },
    );

    test('new ingress invalidates a late authority result', () async {
      await continuation.begin(cubit, EntryShareAccountAction.login);
      final pending = Completer<EntryShareRecipientOwner?>();
      readAuthority = (_) => pending.future;
      await changeAuth(readyAccount());
      ingress.clear();
      pending.complete(_account);
      await Future<void>.delayed(Duration.zero);
      expect(continuation.active, false);
      expect(continuation.ready, false);
      expect(secrets.key, everyElement(0));
    });

    test(
      'explicit cancellation fences a pending account authority read',
      () async {
        await continuation.begin(cubit, EntryShareAccountAction.login);
        final pending = Completer<EntryShareRecipientOwner?>();
        readAuthority = (_) => pending.future;
        await changeAuth(readyAccount());
        continuation.cancel(continuation.generation);
        pending.complete(_account);
        await Future<void>.delayed(Duration.zero);
        expect(continuation.active, false);
        expect(continuation.ready, false);
        expect(secrets.key, everyElement(0));
        verify(() => remote.close()).called(1);
      },
    );

    test('stale cancellation cannot discard a replacement reception', () async {
      await continuation.begin(cubit, EntryShareAccountAction.login);
      final staleGeneration = continuation.generation;
      continuation.cancel(staleGeneration);
      await cubit.close();
      secrets = EntryShareSecrets(
        key: Uint8List(32)..fillRange(0, 32, 3),
        accessToken: Uint8List(32)..fillRange(0, 32, 4),
      );
      cubit = makeCubit();
      await continuation.begin(cubit, EntryShareAccountAction.login);
      continuation.cancel(staleGeneration);
      expect(continuation.active, true);
      expect(secrets.key, everyElement(3));
      continuation.cancel(continuation.generation);
      expect(continuation.active, false);
      expect(secrets.key, everyElement(0));
    });

    for (final transition in [
      'logout',
      'lock',
      'account',
      'key',
      'permission',
      'organization',
    ]) {
      test(
        'bound account replacement discards transfer: $transition',
        () async {
          await continuation.begin(cubit, EntryShareAccountAction.login);
          owner = _account;
          final ready = readyAccount();
          await changeAuth(ready);
          expect(continuation.ready, true);
          if (transition == 'organization') {
            owner = (
              principalId: _account.principalId,
              organizationId: 'other',
              authorizationGeneration: '7',
              keyGeneration: 1,
            );
          }
          await changeAuth(switch (transition) {
            'logout' => const AuthLoading(),
            'lock' => ready.copyWith(isVaultLocked: true, clearKeys: true),
            'account' => ready.copyWith(userId: 'another-account'),
            'key' => ready.copyWith(privateKey: Uint8List(32)),
            'permission' => ready.copyWith(permissions: 16),
            _ => ready.copyWith(),
          });
          expect(continuation.active, false);
          expect(secrets.key, everyElement(0));
        },
      );
    }

    test(
      'cancel while final claim is pending closes any late result',
      () async {
        await continuation.begin(cubit, EntryShareAccountAction.login);
        owner = _account;
        await changeAuth(readyAccount());
        final pending = Completer<EntryShareRecipientOwner?>();
        final claim = continuation.take(
          version: ingress.version,
          owner: _account,
          ownerReader: () => pending.future,
        );
        continuation.clear();
        pending.complete(_account);
        expect(await claim, isNull);
        expect(secrets.key, everyElement(0));
      },
    );
  });

  test(
    'account transfer keeps the received copy, original session and ACK',
    () async {
      await cubit.open();
      await cubit.receive();
      await cubit.confirmDisplay();
      final snapshot = cubit.state.snapshot;
      final lifetime = cubit.lifetime;
      final transfer = (await cubit.detachForAccount())!;
      addTearDown(transfer.dispose);
      expect(cubit.state.snapshot, isNull);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      await cubit.close();
      verifyNever(() => remote.close());
      expect(secrets.key, isNot(everyElement(0)));
      owner = _account;
      final resumed = (await transfer.resume(
        owner: _account,
        ownerReader: () async => owner,
      ))!;
      addTearDown(resumed.close);
      expect(transfer.isAvailable, false);
      expect(identical(resumed.lifetime, lifetime), true);
      expect(identical(resumed.state.snapshot, snapshot), true);
      expect(resumed.state.confirmation, EntryShareConfirmation.confirmed);
      expect(await resumed.receive(), EntryShareReceptionOutcome.ignored);
      expect(
        await resumed.confirmDisplay(),
        EntryShareReceptionOutcome.ignored,
      );
      verify(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).called(1);
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verify(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      await resumed.end();
      verify(
        () => remote.end(
          _shareId,
          session,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(secrets.key, everyElement(0));
    },
  );

  test(
    'account choice before opening does not consume or create a receiver session',
    () async {
      final transfer = (await cubit.detachForAccount())!;
      addTearDown(transfer.dispose);
      final resumed = (await transfer.resume(
        owner: _account,
        ownerReader: () async => _account,
      ))!;
      addTearDown(resumed.close);
      expect(resumed.state.phase, EntryShareReceptionPhase.welcome);
      verifyNever(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      );
      await resumed.open();
      verify(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      ).called(1);
      verifyNever(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
    },
  );

  test(
    'account transfer preserves OTP retry generation and verified secret',
    () async {
      session = makeSession(mode: 'namedRecipient', protection: 'pin');
      await cubit.open();
      await cubit.verifySecret('123456');
      var attempts = 0;
      when(
        () => remote.requestOtp(
          any(),
          any(),
          generation: any(named: 'generation'),
          language: any(named: 'language'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        if (attempts++ == 0) throw const EntryShareRecipientRequestException();
      });
      await cubit.requestOtp('pl');
      final transfer = (await cubit.detachForAccount())!;
      addTearDown(transfer.dispose);
      final resumed = (await transfer.resume(
        owner: _account,
        ownerReader: () async => _account,
      ))!;
      addTearDown(resumed.close);
      expect(resumed.state.secretVerified, true);
      expect(resumed.state.otpRetry, true);
      await resumed.requestOtp('pl');
      verify(
        () => remote.requestOtp(
          _shareId,
          session,
          generation: 1,
          language: 'pl',
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2);
      await resumed.verifyOtp('654321');
      expect(resumed.state.gatesReady, true);
    },
  );

  test(
    'detach is single-flight and cannot race a receiver operation',
    () async {
      final barrier = Completer<EntryShareRecipientOwner?>();
      ownerReader = () => barrier.future;
      final first = cubit.detachForAccount();
      expect(await cubit.detachForAccount(), isNull);
      expect(await cubit.open(), EntryShareReceptionOutcome.ignored);
      barrier.complete(_guest);
      final transfer = (await first)!;
      transfer.dispose();
      expect(secrets.key, everyElement(0));
      verifyNever(
        () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
      );
    },
  );

  test('owner replacement while detaching destroys the old receipt', () async {
    final barrier = Completer<EntryShareRecipientOwner?>();
    ownerReader = () => barrier.future;
    final pending = cubit.detachForAccount();
    barrier.complete(_account);
    expect(await pending, isNull);
    expect(secrets.key, everyElement(0));
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
  });

  test(
    'one transfer cannot resume twice or leak ownership through old disposal',
    () async {
      final transfer = (await cubit.detachForAccount())!;
      addTearDown(transfer.dispose);
      final barrier = Completer<EntryShareRecipientOwner?>();
      final pending = transfer.resume(
        owner: _account,
        ownerReader: () => barrier.future,
      );
      expect(
        await transfer.resume(
          owner: _account,
          ownerReader: () async => _account,
        ),
        isNull,
      );
      barrier.complete(_account);
      final resumed = (await pending)!;
      addTearDown(resumed.close);
      transfer.dispose();
      await cubit.close();
      expect(
        await transfer.resume(
          owner: _account,
          ownerReader: () async => _account,
        ),
        isNull,
      );
      expect(await resumed.open(), EntryShareReceptionOutcome.completed);
      expect(secrets.key, isNot(everyElement(0)));
      await resumed.close();
      expect(secrets.key, everyElement(0));
      verify(() => remote.close()).called(1);
    },
  );

  test(
    'abandoning during independent owner lookup prevents late resume',
    () async {
      final transfer = (await cubit.detachForAccount())!;
      final barrier = Completer<EntryShareRecipientOwner?>();
      final pending = transfer.resume(
        owner: _account,
        ownerReader: () => barrier.future,
      );
      transfer.dispose();
      expect(secrets.key, everyElement(0));
      barrier.complete(_account);
      expect(await pending, isNull);
    },
  );

  test('independent owner mismatch cannot rebind a transfer', () async {
    final transfer = (await cubit.detachForAccount())!;
    expect(
      await transfer.resume(owner: _account, ownerReader: () async => _guest),
      isNull,
    );
    expect(secrets.key, everyElement(0));
    expect(transfer.isAvailable, false);
  });

  test(
    'account transfer retains the original shortened reception expiry',
    () async {
      await cubit.open();
      elapsed = const Duration(minutes: 9);
      final transfer = (await cubit.detachForAccount())!;
      addTearDown(transfer.dispose);
      final resumed = (await transfer.resume(
        owner: _account,
        ownerReader: () async => _account,
      ))!;
      addTearDown(resumed.close);
      expect(resumed.lifetime.remaining, const Duration(minutes: 1));
      elapsed = const Duration(minutes: 10);
      expect(await resumed.revalidate(), false);
      expect(secrets.key, everyElement(0));
    },
  );

  test(
    'transfer expiry while owner lookup is pending clears keys and rejects resume',
    () async {
      await cubit.open();
      final transfer = (await cubit.detachForAccount())!;
      final barrier = Completer<EntryShareRecipientOwner?>();
      final pending = transfer.resume(
        owner: _account,
        ownerReader: () => barrier.future,
      );
      elapsed = const Duration(minutes: 10);
      barrier.complete(_account);
      expect(await pending, isNull);
      expect(secrets.key, everyElement(0));
    },
  );

  test('in-flight delivery cannot detach into account continuation', () async {
    await cubit.open();
    final barrier = Completer<EntryShareDelivery>();
    when(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) => barrier.future);
    final pending = cubit.receive();
    expect(await cubit.detachForAccount(), isNull);
    barrier.complete(_delivery());
    expect(await pending, EntryShareReceptionOutcome.completed);
    expect(cubit.state.snapshot, isNotNull);
  });

  test(
    'suspended email detour cannot detach until foreground revalidation',
    () async {
      session = makeSession(mode: 'namedRecipient');
      await cubit.open();
      await cubit.requestOtp('en');
      expect(cubit.suspendForEmail(), true);
      expect(await cubit.detachForAccount(), isNull);
      await cubit.resumeFromEmail();
      final transfer = (await cubit.detachForAccount())!;
      transfer.dispose();
      expect(secrets.key, everyElement(0));
    },
  );

  test('transfer timer wipes unclaimed capability without a resume action', () {
    fakeAsync((clock) {
      EntryShareReceptionTransfer? transfer;
      cubit.detachForAccount().then((value) => transfer = value);
      clock.flushMicrotasks();
      expect(transfer, isNotNull);
      clock.elapse(const Duration(minutes: 15));
      expect(transfer!.isAvailable, false);
      expect(secrets.key, everyElement(0));
      expect(secrets.accessToken, everyElement(0));
      verify(() => remote.close()).called(1);
    });
  });

  test(
    'owner-reader failure destroys transfer without exposing its exception',
    () async {
      final transfer = (await cubit.detachForAccount())!;
      expect(
        await transfer.resume(
          owner: _account,
          ownerReader: () async => throw StateError('synthetic-only'),
        ),
        isNull,
      );
      expect(transfer.isAvailable, false);
      expect(secrets.key, everyElement(0));
    },
  );

  test('same-account unlock adopts fresh authority only once', () async {
    final guestTransfer = (await cubit.detachForAccount())!;
    final accountCubit = (await guestTransfer.resume(
      owner: _account,
      ownerReader: () async => _account,
    ))!;
    addTearDown(accountCubit.close);
    final transfer = (await accountCubit.detachForAccount())!;
    final unlocked = (
      principalId: _account.principalId,
      organizationId: _account.organizationId,
      authorizationGeneration: _account.authorizationGeneration,
      keyGeneration: 2,
    );
    final resumed = (await transfer.resume(
      owner: unlocked,
      ownerReader: () async => unlocked,
    ))!;
    addTearDown(resumed.close);
    expect(resumed.owner, unlocked);
    expect(await resumed.open(), EntryShareReceptionOutcome.completed);
    verify(
      () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).called(1);
  });

  for (final changed in ['principal', 'organization']) {
    test('existing account transfer rejects a different $changed', () async {
      final guestTransfer = (await cubit.detachForAccount())!;
      final accountCubit = (await guestTransfer.resume(
        owner: _account,
        ownerReader: () async => _account,
      ))!;
      addTearDown(accountCubit.close);
      final transfer = (await accountCubit.detachForAccount())!;
      final replacement = (
        principalId: changed == 'principal' ? 'other' : _account.principalId,
        organizationId: changed == 'organization'
            ? 'other-org'
            : _account.organizationId,
        authorizationGeneration: _account.authorizationGeneration,
        keyGeneration: 2,
      );
      expect(
        await transfer.resume(
          owner: replacement,
          ownerReader: () async => replacement,
        ),
        isNull,
      );
      expect(secrets.key, everyElement(0));
    });
  }

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
