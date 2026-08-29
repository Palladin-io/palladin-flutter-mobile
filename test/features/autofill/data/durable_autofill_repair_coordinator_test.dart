import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/durable_autofill_repair_coordinator.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';

class _MockDurableMemberIndexes extends Mock
    implements DurableMemberIndexUpdates {}

class _MockPreparedAutoFill extends Mock
    implements AutoFillPreparedCacheSynchronizer {}

void main() {
  late StreamController<String> updates;
  late _MockDurableMemberIndexes indexes;
  late _MockPreparedAutoFill autoFill;
  late Object sessionIdentity;
  late AutoFillRepairSession? session;
  late DurableAutoFillRepairCoordinator coordinator;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    updates = StreamController<String>.broadcast(sync: true);
    indexes = _MockDurableMemberIndexes();
    autoFill = _MockPreparedAutoFill();
    sessionIdentity = Object();
    session = AutoFillRepairSession(
      principalId: 'principal-1',
      identity: sessionIdentity,
      privateKey: Uint8List(32),
    );
    when(() => indexes.durableUpdates).thenAnswer((_) => updates.stream);
    when(() => indexes.waitForCurrent(any())).thenAnswer((_) async {});
    when(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenAnswer((_) async {});
    coordinator = DurableAutoFillRepairCoordinator(
      memberIndexes: indexes,
      autoFill: autoFill,
      currentSession: () => session,
      retryDelay: const Duration(hours: 1),
    )..start();
  });

  tearDown(() async {
    await coordinator.dispose();
    await updates.close();
  });

  test(
    'running commit waits, coalesces page signals, and keeps full Vault set',
    () async {
      final releaseCurrent = Completer<void>();
      var waitCalls = 0;
      when(() => indexes.waitForCurrent('vault-a')).thenAnswer((_) {
        waitCalls += 1;
        return releaseCurrent.future;
      });
      coordinator.replaceKnownVaults(const ['vault-a', 'vault-b']);

      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);
      updates
        ..add('vault-a')
        ..add('vault-b');
      await Future<void>.delayed(Duration.zero);
      verifyNever(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      );

      releaseCurrent.complete();
      await coordinator.drainPending();

      final captured =
          verify(
                () => autoFill.synchronizePrepared(
                  privateKey: any(named: 'privateKey'),
                  vaultIds: captureAny(named: 'vaultIds'),
                ),
              ).captured.single
              as Iterable<String>;
      expect(captured.toSet(), {'vault-a', 'vault-b'});
      expect(waitCalls, greaterThanOrEqualTo(2));
      verify(() => indexes.waitForCurrent('vault-b')).called(1);
    },
  );

  test(
    'commit cannot rebuild before complete all-Vault authority is ready',
    () async {
      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);
      verifyNever(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      );

      coordinator.replaceKnownVaults(const ['vault-a', 'vault-b']);
      await coordinator.drainPending();

      final vaultIds =
          verify(
                () => autoFill.synchronizePrepared(
                  privateKey: any(named: 'privateKey'),
                  vaultIds: captureAny(named: 'vaultIds'),
                ),
              ).captured.single
              as Iterable<String>;
      expect(vaultIds.toSet(), {'vault-a', 'vault-b'});
    },
  );

  test(
    'mutation deny keeps commits pending until authoritative rebuild resumes',
    () async {
      final releaseCurrent = Completer<void>();
      when(
        () => indexes.waitForCurrent('vault-a'),
      ).thenAnswer((_) => releaseCurrent.future);
      coordinator.replaceKnownVaults(const ['vault-a', 'vault-b']);

      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);
      final deny = coordinator.suspendRepairs();
      releaseCurrent.complete();
      await coordinator.drainPending();

      verifyNever(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      );

      coordinator.resumeRepairs(deny);
      await coordinator.drainPending();

      final vaultIds =
          verify(
                () => autoFill.synchronizePrepared(
                  privateKey: any(named: 'privateKey'),
                  vaultIds: captureAny(named: 'vaultIds'),
                ),
              ).captured.single
              as Iterable<String>;
      expect(vaultIds.toSet(), {'vault-a', 'vault-b'});
    },
  );

  test('foreground repair cannot bypass an active mutation deny', () async {
    coordinator.replaceKnownVaults(const ['vault-a', 'vault-b']);
    final deny = coordinator.suspendRepairs();

    final blocked = await coordinator.synchronizePreparedIfAllowed(
      privateKey: Uint8List(32),
      vaultIds: const ['vault-a', 'vault-b'],
    );

    expect(blocked, isFalse);
    verifyNever(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    );

    coordinator.resumeRepairs(deny);
    final published = await coordinator.synchronizePreparedIfAllowed(
      privateKey: session!.privateKey,
      vaultIds: const ['vault-a', 'vault-b'],
    );

    expect(published, isTrue);
    final vaultIds =
        verify(
              () => autoFill.synchronizePrepared(
                privateKey: any(named: 'privateKey'),
                vaultIds: captureAny(named: 'vaultIds'),
              ),
            ).captured.single
            as Iterable<String>;
    expect(vaultIds.toSet(), {'vault-a', 'vault-b'});
  });

  test(
    'overlapping mutation and invalidation denies keep one publication owner',
    () async {
      final mutationDeny = coordinator.suspendRepairs();
      final invalidationDeny = coordinator.suspendRepairs();

      final foreground = await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a', 'vault-b'],
      );
      final mutation = await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a', 'vault-b'],
        releasingDenies: {mutationDeny},
      );
      final invalidation = await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a', 'vault-b'],
        releasingDenies: {invalidationDeny},
      );

      expect(foreground, isFalse);
      expect(mutation, isFalse);
      expect(invalidation, isTrue);
      verify(
        () => autoFill.synchronizePrepared(
          privateKey: session!.privateKey,
          vaultIds: any(named: 'vaultIds'),
        ),
      ).called(1);
    },
  );

  test('owned publication consumes only covered durable updates', () async {
    final deny = coordinator.suspendRepairs();
    updates.add('vault-a');
    await Future<void>.delayed(Duration.zero);
    var synchronizeCalls = 0;
    when(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenAnswer((_) async {
      synchronizeCalls += 1;
      if (synchronizeCalls == 1) updates.add('vault-b');
    });

    await coordinator.synchronizePreparedIfAllowed(
      privateKey: session!.privateKey,
      vaultIds: const ['vault-a', 'vault-b'],
      releasingDenies: {deny},
    );
    await coordinator.drainPending();

    verify(
      () => autoFill.synchronizePrepared(
        privateKey: session!.privateKey,
        vaultIds: any(named: 'vaultIds'),
      ),
    ).called(2);
    verify(() => indexes.waitForCurrent('vault-b')).called(1);
    verifyNever(() => indexes.waitForCurrent('vault-a'));
  });

  test('failed repair keeps the commit pending for a later retry', () async {
    var calls = 0;
    when(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) throw StateError('native deny was not confirmed');
    });
    coordinator.replaceKnownVaults(const ['vault-a']);

    updates.add('vault-a');
    await coordinator.drainPending();
    expect(calls, 1);

    await coordinator.drainPending();
    expect(calls, 2);
  });

  test('session replacement aborts the old in-flight repair', () async {
    final releaseCurrent = Completer<void>();
    when(
      () => indexes.waitForCurrent('vault-a'),
    ).thenAnswer((_) => releaseCurrent.future);
    coordinator.replaceKnownVaults(const ['vault-a']);

    updates.add('vault-a');
    await Future<void>.delayed(Duration.zero);
    sessionIdentity = Object();
    session = AutoFillRepairSession(
      principalId: 'principal-1',
      identity: sessionIdentity,
      privateKey: Uint8List(32),
    );
    releaseCurrent.complete();
    await coordinator.drainPending();

    verifyNever(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    );
  });

  test(
    'old drain cannot discard a committed update from the new epoch',
    () async {
      final releaseOldCurrent = Completer<void>();
      var oldWait = true;
      when(() => indexes.waitForCurrent('vault-a')).thenAnswer((_) {
        if (oldWait) return releaseOldCurrent.future;
        return Future<void>.value();
      });
      coordinator.replaceKnownVaults(const ['vault-a']);

      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);

      coordinator.clearSession();
      sessionIdentity = Object();
      session = AutoFillRepairSession(
        principalId: 'principal-2',
        identity: sessionIdentity,
        privateKey: Uint8List(32),
      );
      coordinator.replaceKnownVaults(const ['vault-b']);
      oldWait = false;
      updates.add('vault-b');
      releaseOldCurrent.complete();

      await coordinator.drainPending();
      await Future<void>.delayed(Duration.zero);
      await coordinator.drainPending();

      final captured =
          verify(
                () => autoFill.synchronizePrepared(
                  privateKey: any(named: 'privateKey'),
                  vaultIds: captureAny(named: 'vaultIds'),
                ),
              ).captured.single
              as Iterable<String>;
      expect(captured.toSet(), {'vault-b'});
    },
  );

  test(
    'an unrelated auth-state replacement with the same key still repairs',
    () async {
      final releaseCurrent = Completer<void>();
      when(
        () => indexes.waitForCurrent('vault-a'),
      ).thenAnswer((_) => releaseCurrent.future);
      coordinator.replaceKnownVaults(const ['vault-a']);

      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);
      session = AutoFillRepairSession(
        principalId: 'principal-1',
        identity: sessionIdentity,
        privateKey: Uint8List(32),
      );
      releaseCurrent.complete();
      await coordinator.drainPending();

      verify(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).called(1);
    },
  );
}
