import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_credential_source.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'support/credential_source_fixture.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/autofill-request');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AutoFillRequestController controller;
  late AutoFillSourceAccessService access;
  late List<String> calls;
  Completer<Object?>? heldAuthorization;
  Completer<bool>? heldValidation;
  Map<dynamic, dynamic>? completion;
  var usernameOnly = false;
  var manualWeb = false;

  setUpAll(() => registerFallbackValue(Uint8List(32)));

  setUp(() async {
    calls = [];
    heldAuthorization = null;
    heldValidation = null;
    completion = null;
    usernameOnly = false;
    manualWeb = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'complete') completion = call.arguments as Map;
      return switch (call.method) {
        'pending' => {
          'id': 'request-1',
          'mode': manualWeb ? 'MANUAL_WEB' : 'WEB',
          'verifiedHosts': manualWeb ? [] : ['example.com'],
          if (manualWeb) 'reportedHost': 'example.com',
          if (manualWeb) 'destinationApp': 'Test App (example.app)',
          'usernameOnly': usernameOnly,
          'remainingMs': 30000,
        },
        'beginSourceSession' => 1,
        'invalidateSource' => 2,
        'bind' => 'binding-1',
        'authorizePasswordUnlock' => 'password-authorization',
        'confirmSelection' => 'selection-consent',
        'authenticatePresence' || 'authorizeUnlockedSession' =>
          heldAuthorization == null
              ? 'authorization-1'
              : await heldAuthorization!.future,
        'readBiometricMasterKey' => {
          'masterKey': Uint8List.fromList(List.filled(32, 7)),
          'authorizationToken': 'authorization-1',
        },
        'validate' =>
          heldValidation == null ? true : await heldValidation!.future,
        'complete' => true,
        _ => null,
      };
    });
    access = AutoFillSourceAccessService(channel: channel);
    await access.begin(
      authority: const MemberSyncSessionAuthority(
        principalId: 'principal',
        organizationId: 'org',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      ),
      profileBinding: 'a' * 64,
      accountUnlock: const {},
    );
    calls.clear();
    controller = AutoFillRequestController(channel: channel, source: access);
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> bind() async {
    await controller.poll();
    await controller.bind(
      principalId: 'principal',
      organizationId: 'org',
      sessionId: (await access.ticket()).sessionId,
    );
  }

  for (final cancel in [false, true]) {
    test(
      'local biometric guard grants no fill capability and wipes late key, cancel=$cancel',
      () async {
        await controller.poll();
        final released = Completer<Uint8List?>();
        final key = Uint8List.fromList(List.filled(32, 7));
        final operation = controller.guardLocalBiometricUnlock(
          () => released.future,
        );
        expect(controller.isAuthenticating, isTrue);
        expect(controller.isAuthorized, isFalse);
        if (cancel) await controller.cancel();
        released.complete(key);
        if (cancel) {
          await expectLater(
            operation,
            throwsA(isA<AutoFillRequestInvalidated>()),
          );
          expect(key, everyElement(0));
        } else {
          expect(await operation, same(key));
          expect(controller.isAuthorized, isFalse);
          key.fillRange(0, key.length, 0);
        }
        expect(controller.isAuthenticating, isFalse);
        expect(calls, isNot(contains('authorizeUnlockedSession')));
      },
    );
  }

  test(
    'unlocked app authorizes exact request without another prompt or password',
    () async {
      await bind();
      var validations = 0;
      await controller.authorizeUnlockedSession(
        expectedPrincipalId: 'principal',
        validateCurrentSession: () {
          validations++;
        },
      );
      expect(controller.isAuthorized, isTrue);
      expect(validations, greaterThanOrEqualTo(2));
      expect(calls, contains('authorizeUnlockedSession'));
      expect(calls, isNot(contains('authenticatePresence')));
      expect(calls, isNot(contains('authorizePasswordUnlock')));
    },
  );

  test(
    'wrong principal or already locked app cannot authorize request',
    () async {
      await bind();
      await expectLater(
        controller.authorizeUnlockedSession(
          expectedPrincipalId: 'other',
          validateCurrentSession: () {},
        ),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      await expectLater(
        controller.authorizeUnlockedSession(
          expectedPrincipalId: 'principal',
          validateCurrentSession: () =>
              throw const AutoFillRequestInvalidated(),
        ),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      expect(calls, isNot(contains('authorizeUnlockedSession')));
      expect(controller.isAuthorized, isFalse);
    },
  );

  for (final change in ['lock', 'replacement', 'source']) {
    test(
      'unlocked authorization rejects $change during native handoff',
      () async {
        await bind();
        heldAuthorization = Completer<Object?>();
        var unlocked = true;
        final operation = controller.authorizeUnlockedSession(
          expectedPrincipalId: 'principal',
          validateCurrentSession: () {
            if (!unlocked) throw const AutoFillRequestInvalidated();
          },
        );
        final rejected = expectLater(operation, throwsA(anything));
        while (!calls.contains('authorizeUnlockedSession')) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(controller.isAuthenticating, isFalse);
        if (change == 'lock') unlocked = false;
        if (change == 'replacement') {
          await controller.cancel();
          await bind();
        }
        if (change == 'source') await access.invalidate();
        heldAuthorization!.complete('late-authorization');
        await rejected;
        expect(controller.isAuthorized, isFalse);
      },
    );
  }

  Future<void> fill({String? consentToken}) async {
    final entries = TestAutoFillEntries();
    final index = TestAutoFillIndex()
      ..values = [syntheticAutoFillEntry('chosen', domain: 'example.com')];
    final source = AutoFillCredentialSource(
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
    final guard = controller.captureGuard();
    final selectedSource = await access.ticket();
    final candidate = (await source.candidates(
      vaultIds: ['vault'],
      verifiedHosts: {'example.com'},
      validateRequest: guard,
    )).single;
    try {
      await source.withCredential(
        candidate: candidate,
        selectedHost: 'example.com',
        memberPrivateKey: Uint8List(32),
        validateRequest: guard,
        complete: (credential) => controller.completeCredential(
          credential,
          consentToken: consentToken,
          source: selectedSource,
        ),
      );
    } finally {
      expect(reveal.snapshot.payload, isEmpty);
    }
  }

  test(
    'selected source credential is handed off once and then cleared',
    () async {
      await bind();
      await controller.authenticatePresence();
      await fill();
      expect(completion?['username'], 'synthetic-user');
      expect(completion?['password'], 'synthetic-password');
      expect(
        completion?['effectiveNotAfterMillis'],
        DateTime.utc(2100).millisecondsSinceEpoch,
      );
      expect(controller.isAuthorized, isFalse);
      expect(calls.where((call) => call == 'complete'), hasLength(1));
    },
  );

  for (final usernameStep in [false, true]) {
    test(
      'manual web usernameOnly=$usernameStep requires consent even in an unlocked session',
      () async {
        manualWeb = true;
        usernameOnly = usernameStep;
        await bind();
        await controller.authenticatePresence();
        await expectLater(fill(), throwsA(isA<AutoFillRequestInvalidated>()));
        expect(completion, isNull);
        expect(calls, isNot(contains('complete')));
        await fill(consentToken: 'native-consent');
        expect(completion?['consentToken'], 'native-consent');
        expect(completion?.containsKey('password'), !usernameStep);
      },
    );
  }

  test(
    'manual web bridge never labels reported hosts as verified or accepts ambiguous metadata',
    () {
      final raw = <String, Object?>{
        'id': 'request',
        'mode': 'MANUAL_WEB',
        'verifiedHosts': <String>[],
        'reportedHost': 'example.com',
        'destinationApp': 'Test App (example.app)',
        'usernameOnly': false,
        'remainingMs': 1000,
      };
      final request = AutoFillRequest.parse(raw);
      expect(request.verifiedHosts, isEmpty);
      expect(request.requiresConfirmation, isTrue);
      expect(request.matchingHosts, {'example.com'});
      for (final invalid in <Map<String, Object?>>[
        {'reportedHost': null},
        {'reportedHost': 'http://example.com'},
        {'reportedHost': 'example.com,evil.com'},
        {'reportedHost': '*.example.com'},
        {
          'verifiedHosts': ['example.com'],
        },
        {'destinationApp': ''},
        {'usernameOnly': 'invalid'},
        {'mode': 'WEB'},
      ]) {
        expect(
          () => AutoFillRequest.parse({...raw, ...invalid}),
          throwsA(isA<AutoFillRequestInvalidated>()),
        );
      }
    },
  );

  test('username-only handoff omits password and requires consent', () async {
    usernameOnly = true;
    await bind();
    await controller.authenticatePresence();
    await fill(consentToken: 'native-consent');
    expect(completion?['username'], 'synthetic-user');
    expect(completion?.containsKey('password'), isFalse);
    expect(completion?['consentToken'], 'native-consent');
  });

  test(
    'cancel during native validation prevents credential submission',
    () async {
      await bind();
      await controller.authenticatePresence();
      heldValidation = Completer<bool>();
      final operation = fill();
      await Future<void>.delayed(Duration.zero);
      await controller.cancel();
      heldValidation!.complete(true);
      await expectLater(operation, throwsA(isA<AutoFillRequestInvalidated>()));
      expect(completion, isNull);
    },
  );

  test('pending and binding do not authorize or reveal credentials', () async {
    await bind();
    expect(controller.request?.verifiedHosts, {'example.com'});
    expect(controller.isAuthorized, isFalse);
    expect(calls, ['pending', 'bind']);
  });

  test('native presence authorizes only the current request', () async {
    await bind();
    await controller.authenticatePresence();
    expect(controller.isAuthorized, isTrue);
    await controller.cancel();
    expect(controller.isAuthorized, isFalse);
    expect(controller.request, isNull);
  });

  test('cancel rejects a late native authorization', () async {
    await bind();
    heldAuthorization = Completer<Object?>();
    final pending = controller.authenticatePresence();
    await Future<void>.delayed(Duration.zero);
    await controller.cancel();
    heldAuthorization!.complete('late-authorization');
    await expectLater(pending, throwsA(isA<AutoFillRequestInvalidated>()));
    expect(controller.isAuthorized, isFalse);
  });

  test('key unlock returns bytes only after native authorization', () async {
    await bind();
    final key = await controller.readBiometricMasterKey(
      promptTitle: 'Unlock',
      cancelLabel: 'Cancel',
    );
    expect(key, hasLength(32));
    expect(controller.isAuthorized, isTrue);
    key.fillRange(0, key.length, 0);
    expect(calls.where((call) => call == 'authenticatePresence'), isEmpty);
  });

  test('unbound request cannot start native authentication', () async {
    await controller.poll();
    await expectLater(
      controller.authenticatePresence(),
      throwsA(isA<AutoFillRequestInvalidated>()),
    );
    expect(calls, ['pending']);
  });

  test('concurrent pending notifications share one native read', () async {
    await Future.wait([controller.poll(), controller.poll()]);
    expect(calls, ['pending']);
  });

  test('captured selection guard rejects a replacement binding', () async {
    await bind();
    await controller.authenticatePresence();
    final guard = controller.captureGuard();
    guard();
    await controller.bind(
      principalId: 'other',
      organizationId: 'org',
      sessionId: 'new-session',
    );
    expect(guard, throwsA(isA<AutoFillRequestInvalidated>()));
  });

  test('concurrent authentication cannot open a second prompt', () async {
    await bind();
    heldAuthorization = Completer<Object?>();
    final first = controller.authenticatePresence();
    await Future<void>.delayed(Duration.zero);
    final second = expectLater(
      controller.authenticatePresence(),
      throwsA(isA<AutoFillRequestInvalidated>()),
    );
    heldAuthorization!.complete('authorization-1');
    await second;
    await first;
    expect(calls.where((call) => call == 'authenticatePresence'), hasLength(1));
  });
  test(
    'password proof is one-use and bound before asynchronous crypto',
    () async {
      await bind();
      final authorize = controller.capturePasswordAuthorization();
      expect(controller.isAuthorized, isFalse);
      await authorize();
      expect(controller.isAuthorized, isTrue);
      await expectLater(
        authorize(),
        throwsA(isA<AutoFillRequestInvalidated>()),
      );
      expect(
        calls.where((method) => method == 'authorizePasswordUnlock'),
        hasLength(1),
      );
    },
  );

  test(
    'canceled request cannot authorize a replacement after password crypto',
    () async {
      await bind();
      final old = controller.capturePasswordAuthorization();
      await controller.cancel();
      await bind();
      await expectLater(old(), throwsA(isA<AutoFillRequestInvalidated>()));
      expect(controller.isAuthorized, isFalse);
      expect(calls, isNot(contains('authorizePasswordUnlock')));
    },
  );
  test(
    'source epoch changed during validation rejects old selected plaintext',
    () async {
      await bind();
      await controller.authenticatePresence();
      heldValidation = Completer<bool>();
      final pending = fill();
      final rejected = expectLater(pending, throwsStateError);
      while (!calls.contains('validate')) {
        await Future<void>.delayed(Duration.zero);
      }
      await access.invalidate();
      heldValidation!.complete(true);
      await rejected;
      expect(completion, isNull);
    },
  );
  Future<void> nativeEvent(String method, Object args) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) => done.complete(),
    );
    await done.future;
  }

  test('native invalidation cancels only its original request', () async {
    await bind();
    await controller.authenticatePresence();
    await nativeEvent('invalidated', 'older-request');
    expect(controller.isAuthorized, isTrue);
    await nativeEvent('invalidated', 'request-1');
    expect(controller.request, isNull);
    expect(controller.isAuthorized, isFalse);
    expect(
      calls,
      isNot(contains('cancel')),
      reason:
          'Native invalidation already ended the request; echoing cancellation can background a replacement request',
    );
  });

  test(
    'explicit selection confirmation is fenced to selected source epoch',
    () async {
      await bind();
      await controller.authenticatePresence();
      final index = TestAutoFillIndex()
        ..values = [syntheticAutoFillEntry('chosen', domain: 'example.com')];
      final source = AutoFillCredentialSource(
        memberIndex: index,
        localEntries: TestAutoFillEntries(),
      );
      final candidate = (await source.candidates(
        vaultIds: ['vault'],
        verifiedHosts: {'example.com'},
        validateRequest: controller.captureGuard(),
      )).single;
      final ticket = await access.ticket();
      expect(
        await controller.confirmSelection(
          candidate: candidate,
          selectedHost: 'example.com',
          source: ticket,
        ),
        'selection-consent',
      );
      await access.invalidate();
      await expectLater(
        controller.confirmSelection(
          candidate: candidate,
          selectedHost: 'example.com',
          source: ticket,
        ),
        throwsStateError,
      );
      expect(
        calls.where((method) => method == 'confirmSelection'),
        hasLength(1),
      );
    },
  );
  test(
    'two cold binding consumers share one original native binding',
    () async {
      controller.dispose();
      controller = AutoFillRequestController(
        channel: channel,
        source: access,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => const MemberSyncSessionAuthority(
            principalId: 'principal',
            organizationId: 'org',
            organizationMembershipGeneration: '1',
            offlinePolicy: '24h',
            offlinePolicyVersion: 1,
          ),
          sessionRevision: () => 0,
        ),
      );
      await controller.poll();
      final passwordProof = controller.preparePasswordAuthorization();
      final host = controller.ensureBound();
      final proof = await passwordProof;
      await host;
      expect(calls.where((method) => method == 'bind'), hasLength(1));
      await proof();
      expect(controller.isAuthorized, isTrue);
    },
  );
}
