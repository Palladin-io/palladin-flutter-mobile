import 'dart:async';
import 'package:mobile_palladin/core/storage/biometric_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/source-access');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AutoFillSourceAccessService source;
  late int nativeEpoch;
  late bool active;
  late bool failDeny;
  late List<String> calls;
  const claims = MemberSyncSessionAuthority(
    principalId: 'principal',
    organizationId: 'org',
    organizationMembershipGeneration: '1',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );

  setUp(() {
    nativeEpoch = 0;
    active = false;
    failDeny = false;
    calls = [];
    source = AutoFillSourceAccessService(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'beginSourceSession':
          active = false;
          return ++nativeEpoch;
        case 'invalidateSource':
        case 'revokeSourceSession':
          if (failDeny) throw PlatformException(code: 'SOURCE_UNAVAILABLE');
          expect(args?['sourceEpoch'], nativeEpoch);
          active = false;
          return ++nativeEpoch;
        case 'activateSource':
          expect(args?['sourceEpoch'], nativeEpoch);
          active = true;
          return nativeEpoch;
        default:
          return null;
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> begin() => source.begin(
    authority: claims,
    profileBinding: List.filled(64, 'a').join(),
    accountUnlock: const {'accountId': 'principal'},
  );

  test(
    'begin quarantines until independently validated metadata activates',
    () async {
      await begin();
      expect(active, isFalse);
      final ticket = await source.ticket();
      var checks = 0;
      await source.activate(expected: ticket, validateSource: () => checks++);
      expect(active, isTrue);
      expect(checks, greaterThanOrEqualTo(2));
    },
  );

  test(
    'biometric mutation cannot be activated while its operation is held',
    () async {
      await begin();
      final entered = Completer<void>();
      final release = Completer<void>();
      final mutation = source.withBiometricMutation((ticket) async {
        expect(active, isFalse);
        expect(ticket['sourceEpoch'], nativeEpoch);
        entered.complete();
        await release.future;
      });
      await entered.future;
      final ticket = await source.ticket();
      await expectLater(
        source.activate(expected: ticket, validateSource: () {}),
        throwsStateError,
      );
      release.complete();
      await mutation;
      await source.activate(
        expected: await source.ticket(),
        validateSource: () {},
      );
      expect(active, isTrue);
    },
  );

  test(
    'biometric activity remains set until all operations finish and resets on failure',
    () async {
      await begin();
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      final firstRelease = Completer<void>();
      final secondRelease = Completer<void>();
      final first = source.withBiometricMutation((_) async {
        firstEntered.complete();
        await firstRelease.future;
      });
      await firstEntered.future;
      final second = source.withBiometricMutation((_) async {
        secondEntered.complete();
        await secondRelease.future;
        throw StateError('synthetic operation failure');
      });
      final rejected = expectLater(second, throwsStateError);
      await secondEntered.future;
      expect(source.isBiometricMutationActive, isTrue);
      firstRelease.complete();
      await first;
      expect(source.isBiometricMutationActive, isTrue);
      secondRelease.complete();
      await rejected;
      expect(source.isBiometricMutationActive, isFalse);
    },
  );

  test('failed biometric bootstrap resets activity', () async {
    final unavailable = AutoFillSourceAccessService(
      channel: channel,
      loadConfiguration: () async =>
          throw StateError('synthetic bootstrap failure'),
    );
    final operation = unavailable.withBiometricMutation((_) async {});
    expect(unavailable.isBiometricMutationActive, isTrue);
    await expectLater(operation, throwsStateError);
    expect(unavailable.isBiometricMutationActive, isFalse);
  });

  test('failed durable deny aborts the sensitive mutation', () async {
    await begin();
    failDeny = true;
    var invoked = false;
    await expectLater(
      source.withBiometricMutation((_) async {
        invoked = true;
      }),
      throwsA(isA<PlatformException>()),
    );
    expect(invoked, isFalse);
    expect(source.isBiometricMutationActive, isFalse);
    await expectLater(
      source.activate(expected: await source.ticket(), validateSource: () {}),
      throwsStateError,
    );
  });

  test('new owner invalidates an older metadata activation ticket', () async {
    await begin();
    final stale = await source.ticket();
    final owner = await source.invalidate();
    source.complete(owner);
    await expectLater(
      source.activate(expected: stale, validateSource: () {}),
      throwsStateError,
    );
    expect(calls.where((name) => name == 'activateSource'), isEmpty);
    await source.activate(
      expected: await source.ticket(),
      validateSource: () {},
    );
    expect(active, isTrue);
  });

  test('biometric operation cannot borrow a later owner epoch', () async {
    await begin();
    var called = false;
    final first = source.withBiometricMutation((_) async {
      called = true;
    });
    final second = source.invalidate();
    await expectLater(first, throwsStateError);
    source.complete(await second);
    expect(called, isFalse);
    expect(active, isFalse);
  });
  AutoFillSourceConfiguration configuration() => AutoFillSourceConfiguration(
    authority: claims,
    profileBinding: List.filled(64, 'a').join(),
    accountUnlock: const {'accountId': 'principal'},
    validateCurrent: () {},
  );

  test(
    'cold availability and ticket bootstrap share one native session',
    () async {
      final loaded = Completer<AutoFillSourceConfiguration>();
      var loads = 0;
      source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: () {
          loads++;
          return loaded.future;
        },
      );
      final availability = source.biometricSourceTicket();
      final request = source.ticket();
      loaded.complete(configuration());
      expect((await availability)['sessionId'], (await request).sessionId);
      expect(loads, 1);
      expect(calls.where((name) => name == 'beginSourceSession'), hasLength(1));
    },
  );

  test(
    'failed bootstrap is retryable without a completed account cache',
    () async {
      var loads = 0;
      source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: () async {
          if (++loads == 1) throw StateError('synthetic failure');
          return configuration();
        },
      );
      await expectLater(source.ticket(), throwsStateError);
      await source.ticket();
      expect(loads, 2);
    },
  );

  test('old bootstrap cannot replace a newer explicit identity', () async {
    final loaded = Completer<AutoFillSourceConfiguration>();
    source = AutoFillSourceAccessService(
      channel: channel,
      loadConfiguration: () => loaded.future,
    );
    final old = source.ticket();
    final rejected = expectLater(old, throwsStateError);
    await begin();
    final current = await source.ticket();
    loaded.complete(configuration());
    await rejected;
    expect((await source.ticket()).sessionId, current.sessionId);
    expect(calls.where((name) => name == 'beginSourceSession'), hasLength(1));
  });

  test(
    'proven prewrite cancellation allows authoritative reconciliation',
    () async {
      await begin();
      await expectLater(
        source.withBiometricMutation<void>((_) async {
          throw const BiometricMutationCanceledWithoutChanges();
        }),
        throwsA(isA<BiometricMutationCanceledWithoutChanges>()),
      );
      expect(active, isFalse);
      await source.activate(
        expected: await source.ticket(),
        validateSource: () {},
      );
      expect(active, isTrue);
    },
  );

  test('unknown protected write failure retains denial', () async {
    await begin();
    await expectLater(
      source.withBiometricMutation<void>((_) async {
        throw StateError('synthetic write failure');
      }),
      throwsStateError,
    );
    await expectLater(
      source.activate(expected: await source.ticket(), validateSource: () {}),
      throwsStateError,
    );
    expect(active, isFalse);
  });
  test(
    'availability arriving during native begin shares the same bootstrap',
    () async {
      final nativeEntered = Completer<void>();
      final nativeRelease = Completer<void>();
      var begins = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'beginSourceSession') {
          begins++;
          if (!nativeEntered.isCompleted) nativeEntered.complete();
          await nativeRelease.future;
          return ++nativeEpoch;
        }
        return null;
      });
      source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: () async => configuration(),
      );
      final first = source.ticket();
      await nativeEntered.future;
      final second = source.biometricSourceTicket();
      nativeRelease.complete();
      final results = await Future.wait([first, second]);
      expect(begins, 1);
      expect(
        (results[0] as AutoFillSourceTicket).sessionId,
        (results[1] as Map)['sessionId'],
      );
    },
  );
  test(
    'ciphertext write stays denied through commit and blocks activation',
    () async {
      await begin();
      final entered = Completer<void>();
      final committed = Completer<void>();
      final write = source.withCiphertextMutation(() async {
        expect(active, isFalse);
        entered.complete();
        await committed.future;
      });
      await entered.future;
      var activated = false;
      committed.complete();
      await write;
      await source.activate(
        expected: await source.ticket(),
        validateSource: () {
          activated = true;
        },
      );
      expect(activated, isTrue);
    },
  );
  test(
    'live revoke retains a quarantined cleanup ticket without rebootstrap',
    () async {
      await begin();
      await source.revokeAccess();
      final ticket = await source.biometricSourceTicket();
      expect(ticket['sourceEpoch'], nativeEpoch);
      expect(active, isFalse);
      await expectLater(
        source.activate(expected: await source.ticket(), validateSource: () {}),
        throwsStateError,
      );
      expect(calls.where((name) => name == 'beginSourceSession'), hasLength(1));
    },
  );

  test(
    'cold revoke cannot borrow a newer source session after snapshot await',
    () async {
      final read = Completer<Object?>();
      final entered = Completer<void>();
      var revokes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'sourceSnapshot') {
          entered.complete();
          return read.future;
        }
        if (call.method == 'beginSourceSession') return ++nativeEpoch;
        if (call.method == 'revokeSource') {
          revokes++;
          return ++nativeEpoch;
        }
        return null;
      });
      final old = source.revokeAccess();
      final rejected = expectLater(old, throwsStateError);
      await entered.future;
      final newer = begin();
      read.complete({'sourceEpoch': 1, 'profileDigest': 'synthetic'});
      await rejected;
      await newer;
      expect(revokes, 0);
    },
  );
  test(
    'old queued ciphertext write cannot borrow replacement account bootstrap',
    () async {
      await begin();
      var wrote = false;
      final old = source.withCiphertextMutation(() async {
        wrote = true;
      });
      final rejected = expectLater(old, throwsStateError);
      await begin();
      await rejected;
      expect(wrote, isFalse);
    },
  );
  test(
    'security invalidation cancels authorization but owner is repairable',
    () async {
      await begin();
      final owner = await source.invalidate(revokeAuthorization: true);
      expect(calls.last, 'revokeSourceSession');
      source.complete(owner);
      await source.activate(
        expected: await source.ticket(),
        validateSource: () {},
      );
      expect(active, isTrue);
    },
  );
  test(
    'true session transition denies old source before any replacement begin',
    () async {
      await begin();
      final denyEntered = Completer<void>();
      final releaseDeny = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'sourceSnapshot') {
          return {'sourceEpoch': nativeEpoch, 'profileDigest': 'synthetic'};
        }
        if (call.method == 'revokeSourceSession') {
          denyEntered.complete();
          await releaseDeny.future;
          return ++nativeEpoch;
        }
        if (call.method == 'beginSourceSession') return ++nativeEpoch;
        return null;
      });
      final transition = source.transitionSession();
      await denyEntered.future;
      final replacement = begin();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((name) => name == 'beginSourceSession'), hasLength(1));
      releaseDeny.complete();
      await transition;
      await replacement;
      expect(calls.where((name) => name == 'beginSourceSession'), hasLength(2));
    },
  );

  test('failed transition denial blocks replacement bootstrap', () async {
    await begin();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'sourceSnapshot') {
        return {'sourceEpoch': nativeEpoch, 'profileDigest': 'synthetic'};
      }
      if (call.method == 'revokeSourceSession') {
        throw PlatformException(code: 'unavailable');
      }
      if (call.method == 'beginSourceSession') {
        fail('Replacement cannot begin before denial');
      }
      return null;
    });
    await expectLater(
      source.transitionSession(),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(begin(), throwsA(isA<PlatformException>()));
  });
  test(
    'cold security invalidation denies before account GET and survives bootstrap',
    () async {
      final config = Completer<AutoFillSourceConfiguration>();
      nativeEpoch = 10;
      bool? forced;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'sourceSnapshot') {
          return {'sourceEpoch': nativeEpoch, 'profileDigest': 'synthetic'};
        }
        if (call.method == 'revokeSource') return ++nativeEpoch;
        if (call.method == 'beginSourceSession') {
          forced = (call.arguments as Map)['forceQuarantine'] as bool;
          return ++nativeEpoch;
        }
        if (call.method == 'activateSource') return nativeEpoch;
        return null;
      });
      source = AutoFillSourceAccessService(
        channel: channel,
        loadConfiguration: () => config.future,
      );
      final starting = source.ensureSession();
      final owner = await source.invalidate(revokeAuthorization: true);
      expect(calls, contains('revokeSource'));
      expect(calls, isNot(contains('beginSourceSession')));
      config.complete(configuration());
      await starting;
      expect(forced, isTrue);
      await expectLater(
        source.activate(expected: await source.ticket(), validateSource: () {}),
        throwsStateError,
      );
      source.complete(owner);
      await source.activate(
        expected: await source.ticket(),
        validateSource: () {},
      );
    },
  );
}
