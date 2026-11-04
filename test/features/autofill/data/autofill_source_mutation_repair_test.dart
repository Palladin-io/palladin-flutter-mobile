import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_mutation_repair.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/source-mutation-repair');
  const claims = MemberSyncSessionAuthority(
    principalId: 'p',
    organizationId: 'o',
    organizationMembershipGeneration: '1',
    offlinePolicy: '24h',
    offlinePolicyVersion: 1,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AutoFillSourceAccessService source;
  late AutoFillSourceMutationRepair repair;
  late int epoch;
  late int activations;
  late List<String> calls;
  Completer<void>? denialGate;
  Completer<void>? denialEntered;
  Future<void> begin() => source.begin(
    authority: claims,
    profileBinding: 'a' * 64,
    accountUnlock: const {},
  );
  Future<void> activate() async =>
      source.activate(expected: await source.ticket(), validateSource: () {});

  setUp(() async {
    epoch = 0;
    activations = 0;
    calls = [];
    denialGate = null;
    denialEntered = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'revokeSourceSession' && denialGate != null) {
        denialEntered!.complete();
        await denialGate!.future;
      }
      if (call.method == 'activateSource') {
        activations++;
        return epoch;
      }
      return ++epoch;
    });
    source = AutoFillSourceAccessService(channel: channel);
    await begin();
    repair = AutoFillSourceMutationRepair(source);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'definitive mutation stays denied until authoritative refresh completes',
    () async {
      await repair.invalidate();
      await repair.markCommitted();
      await expectLater(activate(), throwsStateError);
      final gate = Completer<void>();
      final refreshing = repair.prepare(() => gate.future);
      await expectLater(activate(), throwsStateError);
      gate.complete();
      await refreshing;
      await activate();
      expect(activations, 1);
      expect(calls, contains('revokeSourceSession'));
    },
  );

  test(
    'failed refresh retains deny and retries without a new invalidation',
    () async {
      await repair.invalidate();
      await repair.markCommitted();
      await expectLater(
        repair.prepare(() async => throw StateError('offline')),
        throwsStateError,
      );
      await expectLater(activate(), throwsStateError);
      expect(await repair.prepare(() async => 7), 7);
      await activate();
    },
  );

  test(
    'routine refresh never releases an ambiguous or in-flight mutation',
    () async {
      await repair.invalidate();
      await repair.prepare(() async {});
      await expectLater(activate(), throwsStateError);
      expect(activations, 0);
    },
  );

  test('new mutation during refresh cannot borrow prior completion', () async {
    await repair.invalidate();
    await repair.markCommitted();
    final gate = Completer<void>();
    final refreshing = repair.prepare(() => gate.future);
    await repair.invalidate();
    gate.complete();
    await refreshing;
    await expectLater(activate(), throwsStateError);
    await repair.markCommitted();
    await repair.prepare(() async {});
    await activate();
  });

  test('replaced account cannot finish old reconciliation', () async {
    await repair.invalidate();
    await repair.markCommitted();
    final gate = Completer<void>();
    final refreshing = repair.prepare(() => gate.future);
    final rejected = expectLater(refreshing, throwsStateError);
    await begin();
    gate.complete();
    await rejected;
    expect(activations, 0);
  });

  test(
    'old committed owners cannot poison replacement account repair',
    () async {
      await repair.invalidate();
      await repair.markCommitted();
      await begin();
      await repair.invalidate();
      await repair.markCommitted();
      await repair.prepare(() async {});
      await activate();
      expect(activations, 1);
    },
  );
  test(
    'held invalidation cannot mark replacement account work committed',
    () async {
      denialGate = Completer<void>();
      denialEntered = Completer<void>();
      final stale = repair.invalidateCommitted();
      final rejected = expectLater(stale, throwsStateError);
      await denialEntered!.future;
      final replacement = begin();
      denialGate!.complete();
      await rejected;
      await replacement;
      denialGate = null;
      await repair.invalidate();
      await repair.prepare(() async {});
      await expectLater(activate(), throwsStateError);
    },
  );
  test(
    'committed invalidation never completes an overlapping pending mutation',
    () async {
      denialGate = Completer<void>();
      denialEntered = Completer<void>();
      final committed = repair.invalidateCommitted();
      await denialEntered!.future;
      final pending = repair.invalidate();
      final release = denialGate!;
      denialGate = null;
      release.complete();
      await Future.wait([committed, pending]);
      await repair.prepare(() async {});
      await expectLater(activate(), throwsStateError);
    },
  );
  test('standalone committed change denies before refresh', () async {
    await activate();
    await repair.markCommitted();
    await expectLater(activate(), throwsStateError);
    await repair.prepare(() async {});
    await activate();
    expect(activations, 2);
  });
  test(
    'concurrent successful reconciliation does not poison the later reader',
    () async {
      await repair.invalidate();
      await repair.markCommitted();
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final first = repair.prepare(() => firstGate.future);
      final second = repair.prepare(() => secondGate.future);
      firstGate.complete();
      await first;
      await activate();
      secondGate.complete();
      await second;
      await activate();
    },
  );
}
