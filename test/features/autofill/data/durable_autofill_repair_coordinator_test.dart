import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
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
    'new commit queues publication behind the active foreground repair',
    () async {
      final firstNative = Completer<void>();
      final followupNative = Completer<void>();
      var calls = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) {
        calls++;
        return calls == 1 ? firstNative.future : followupNative.future;
      });
      final first = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
      );
      updates.add('vault-a');
      var secondFinished = false;
      final second = coordinator
          .synchronizePreparedIfAllowed(
            privateKey: session!.privateKey,
            vaultIds: const ['vault-a'],
          )
          .then((value) {
            secondFinished = true;
            return value;
          });
      final earlyCalls = calls;
      firstNative.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      final lateCalls = calls;
      final prematurelyAcknowledged = secondFinished;
      followupNative.complete();
      await second;
      await coordinator.drainPending();
      expect(earlyCalls, 1);
      expect(lateCalls, 2);
      expect(prematurelyAcknowledged, isFalse);
      expect(calls, 2);
    },
  );

  test(
    'latest complete Vault set rejects stale queued sets without resurrecting removals',
    () async {
      final native = Completer<void>();
      final published = <Set<String>>[];
      var active = 0;
      var peak = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((call) async {
        published.add(
          Set<String>.from(call.namedArguments[#vaultIds] as Iterable<String>),
        );
        active++;
        if (active > peak) peak = active;
        try {
          if (published.length == 1) await native.future;
        } finally {
          active--;
        }
      });
      final first = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['a'],
      );
      final stale = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['a', 'b'],
      );
      final rejected = expectLater(stale, throwsStateError);
      final latest = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['c'],
      );
      native.complete();
      await first;
      await rejected;
      await latest;
      expect(published, [
        {'a'},
        {'c'},
      ]);
      expect(peak, 1);
    },
  );

  test(
    'new authorized owner waits for failed old publication then repairs',
    () async {
      final native = Completer<void>();
      var calls = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) {
        calls++;
        return calls == 1 ? native.future : Future<void>.value();
      });
      final first = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['a'],
      );
      final rejected = expectLater(first, throwsStateError);
      final deny = coordinator.suspendRepairs();
      final next = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['a'],
        releasingDenies: {deny},
      );
      expect(calls, 1);
      native.completeError(StateError('old native failure'));
      await rejected;
      expect(await next, isTrue);
      expect(calls, 2);
    },
  );

  for (final boundary in ['deny', 'lock', 'identity']) {
    test('queued foreground publication stops after $boundary', () async {
      final native = Completer<void>();
      var calls = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) {
        calls++;
        return native.future;
      });
      final first = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
      );
      updates.add('vault-a');
      final second = coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
      );
      final rejected = expectLater(second, throwsStateError);
      switch (boundary) {
        case 'deny':
          coordinator.suspendRepairs();
        case 'lock':
          coordinator.clearSession();
          session = null;
        case 'identity':
          session = AutoFillRepairSession(
            principalId: 'principal-1',
            identity: Object(),
            privateKey: Uint8List(32),
          );
      }
      native.complete();
      await first;
      await rejected;
      expect(calls, 1);
    });
  }

  test(
    'new mutation during completed owner preparation stays denied',
    () async {
      final ownerA = coordinator.suspendRepairs();
      final completedOwners = {ownerA};
      final prepared = Completer<void>();
      final attemptA = () async {
        await prepared.future;
        return coordinator.synchronizePreparedIfAllowed(
          privateKey: session!.privateKey,
          vaultIds: const ['vault-a'],
          releasingDenies: completedOwners,
        );
      }();
      final ownerB = coordinator.suspendRepairs();
      prepared.complete();
      expect(await attemptA, isFalse);
      expect(
        await coordinator.synchronizePreparedIfAllowed(
          privateKey: session!.privateKey,
          vaultIds: const ['vault-a'],
        ),
        isFalse,
      );
      verifyNever(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      );
      expect(
        await coordinator.synchronizePreparedIfAllowed(
          privateKey: session!.privateKey,
          vaultIds: const ['vault-a'],
          releasingDenies: {ownerB},
        ),
        isTrue,
      );
      verify(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).called(1);
    },
  );

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
    'foreground and durable repair share the same committed publication',
    () async {
      final current = Completer<void>();
      when(
        () => indexes.waitForCurrent('vault-a'),
      ).thenAnswer((_) => current.future);
      coordinator.replaceKnownVaults(const ['vault-a']);
      var rebuilds = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) async {
        rebuilds++;
      });
      updates.add('vault-a');
      await Future<void>.delayed(Duration.zero);
      await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
      );
      current.complete();
      await coordinator.drainPending();
      expect(rebuilds, 1);
    },
  );

  test('foreground joins an in-flight durable publication', () async {
    final native = Completer<void>();
    var rebuilds = 0;
    when(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).thenAnswer((_) {
      rebuilds++;
      return native.future;
    });
    coordinator.replaceKnownVaults(const ['vault-a']);
    updates.add('vault-a');
    await Future<void>.delayed(Duration.zero);
    final foreground = coordinator.synchronizePreparedIfAllowed(
      privateKey: session!.privateKey,
      vaultIds: const ['vault-a'],
    );
    expect(rebuilds, 1);
    native.complete();
    expect(await foreground, isTrue);
    await coordinator.drainPending();
    expect(rebuilds, 1);
  });

  test(
    'native deny requires a new publication even without a new commit',
    () async {
      await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
      );
      final deny = coordinator.suspendRepairs();
      await coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a'],
        releasingDenies: {deny},
      );
      verify(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).called(2);
    },
  );

  test(
    'explicit foreground repair retries after completed native publication',
    () async {
      // Native quarantine/biometric invalidation can happen without a Dart commit.
      for (var attempt = 0; attempt < 2; attempt++) {
        await coordinator.synchronizePreparedIfAllowed(
          privateKey: session!.privateKey,
          vaultIds: const ['vault-a'],
        );
      }
      verify(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).called(2);
    },
  );

  test('changed complete Vault set requires another publication', () async {
    await coordinator.synchronizePreparedIfAllowed(
      privateKey: session!.privateKey,
      vaultIds: const ['vault-a'],
    );
    await coordinator.synchronizePreparedIfAllowed(
      privateKey: session!.privateKey,
      vaultIds: const ['vault-a', 'vault-b'],
    );
    verify(
      () => autoFill.synchronizePrepared(
        privateKey: any(named: 'privateKey'),
        vaultIds: any(named: 'vaultIds'),
      ),
    ).called(2);
  });

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

  test(
    'foreground failure without a commit retries native publication once',
    () {
      fakeAsync((clock) {
        var attempts = 0;
        var available = false;
        when(
          () => autoFill.synchronizePrepared(
            privateKey: any(named: 'privateKey'),
            vaultIds: any(named: 'vaultIds'),
          ),
        ).thenAnswer((invocation) async {
          attempts++;
          expect(invocation.namedArguments[#vaultIds], {'vault-a', 'vault-b'});
          if (attempts == 1) throw StateError('transient native failure');
          available = true;
        });
        coordinator
            .synchronizePreparedIfAllowed(
              privateKey: session!.privateKey,
              vaultIds: const ['vault-a', 'vault-b'],
            )
            .catchError((Object error) {
              expect(error, isStateError);
              return false;
            });
        clock.flushMicrotasks();
        expect(available, isFalse);
        clock.elapse(const Duration(hours: 1));
        expect(available, isTrue);
        expect(attempts, 2);
        clock.elapse(const Duration(hours: 4));
        expect(attempts, 2);
        verifyNever(() => indexes.waitForCurrent(any()));
      });
    },
  );

  test('successful foreground repair cancels its pending retry', () {
    fakeAsync((clock) {
      var attempts = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw StateError('transient native failure');
      });
      coordinator
          .synchronizePreparedIfAllowed(
            privateKey: session!.privateKey,
            vaultIds: const ['vault-a'],
          )
          .catchError((Object _) => false);
      clock.flushMicrotasks();
      coordinator.synchronizePreparedIfAllowed(
        privateKey: session!.privateKey,
        vaultIds: const ['vault-a', 'vault-b'],
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(hours: 2));
      expect(attempts, 2);
    });
  });

  test(
    'permanent durable failure retries once, preserving pending work for new events',
    () {
      fakeAsync((clock) {
        unawaited(coordinator.dispose());
        coordinator = DurableAutoFillRepairCoordinator(
          memberIndexes: indexes,
          autoFill: autoFill,
          currentSession: () => session,
          retryDelay: const Duration(hours: 1),
        )..start();
        var attempts = 0;
        var failing = true;
        when(
          () => autoFill.synchronizePrepared(
            privateKey: any(named: 'privateKey'),
            vaultIds: any(named: 'vaultIds'),
          ),
        ).thenAnswer((_) async {
          attempts++;
          if (failing) throw StateError('native unavailable');
        });
        coordinator.replaceKnownVaults(const ['vault-a']);
        updates.add('vault-a');
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 5));
        expect(attempts, 2);
        updates.add('vault-a');
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 5));
        expect(attempts, 4);
        failing = false;
        coordinator.synchronizePreparedIfAllowed(
          privateKey: session!.privateKey,
          vaultIds: const ['vault-a'],
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 5));
        expect(attempts, 5);
        coordinator.drainPending();
        clock.flushMicrotasks();
        expect(attempts, 5);
      });
    },
  );

  for (final change in ['lock', 'identity', 'principal', 'deny']) {
    test('durable automatic retry stops after $change', () {
      fakeAsync((clock) {
        unawaited(coordinator.dispose());
        coordinator = DurableAutoFillRepairCoordinator(
          memberIndexes: indexes,
          autoFill: autoFill,
          currentSession: () => session,
          retryDelay: const Duration(hours: 1),
        )..start();
        var attempts = 0;
        when(
          () => autoFill.synchronizePrepared(
            privateKey: any(named: 'privateKey'),
            vaultIds: any(named: 'vaultIds'),
          ),
        ).thenAnswer((_) async {
          attempts++;
          throw StateError('native unavailable');
        });
        coordinator.replaceKnownVaults(const ['vault-a']);
        updates.add('vault-a');
        clock.flushMicrotasks();
        switch (change) {
          case 'lock':
            session = null;
            coordinator.clearSession();
          case 'identity':
            session = AutoFillRepairSession(
              principalId: 'principal-1',
              identity: Object(),
              privateKey: Uint8List(32),
            );
          case 'principal':
            session = AutoFillRepairSession(
              principalId: 'principal-2',
              identity: sessionIdentity,
              privateKey: Uint8List(32),
            );
          case 'deny':
            coordinator.suspendRepairs();
        }
        clock.elapse(const Duration(hours: 5));
        expect(attempts, 1);
      });
    });
  }

  test('permanent foreground failure has only one automatic retry', () {
    fakeAsync((clock) {
      var attempts = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) async {
        attempts++;
        throw StateError('native unavailable');
      });
      coordinator
          .synchronizePreparedIfAllowed(
            privateKey: session!.privateKey,
            vaultIds: const ['vault-a'],
          )
          .catchError((Object _) => false);
      clock.flushMicrotasks();
      clock.elapse(const Duration(hours: 5));
      expect(attempts, 2);
    });
  });

  for (final change in ['lock', 'identity', 'principal', 'deny', 'dispose']) {
    test('foreground retry stops after $change', () {
      fakeAsync((clock) {
        var attempts = 0;
        when(
          () => autoFill.synchronizePrepared(
            privateKey: any(named: 'privateKey'),
            vaultIds: any(named: 'vaultIds'),
          ),
        ).thenAnswer((_) async {
          attempts++;
          throw StateError('native unavailable');
        });
        coordinator
            .synchronizePreparedIfAllowed(
              privateKey: session!.privateKey,
              vaultIds: const ['vault-a'],
            )
            .catchError((Object _) => false);
        clock.flushMicrotasks();
        switch (change) {
          case 'lock':
            coordinator.clearSession();
            session = null;
          case 'identity':
            session = AutoFillRepairSession(
              principalId: 'principal-1',
              identity: Object(),
              privateKey: Uint8List(32),
            );
          case 'principal':
            session = AutoFillRepairSession(
              principalId: 'principal-2',
              identity: sessionIdentity,
              privateKey: Uint8List(32),
            );
          case 'deny':
            coordinator.suspendRepairs();
          case 'dispose':
            unawaited(coordinator.dispose());
        }
        clock.elapse(const Duration(hours: 2));
        expect(attempts, 1);
      });
    });
  }

  test('failed owned deny is never converted into an ownerless retry', () {
    fakeAsync((clock) {
      var attempts = 0;
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) async {
        attempts++;
        throw StateError('native unavailable');
      });
      final deny = coordinator.suspendRepairs();
      coordinator
          .synchronizePreparedIfAllowed(
            privateKey: session!.privateKey,
            vaultIds: const ['vault-a'],
            releasingDenies: {deny},
          )
          .catchError((Object _) => false);
      clock.flushMicrotasks();
      clock.elapse(const Duration(hours: 2));
      coordinator
          .synchronizePreparedIfAllowed(
            privateKey: session!.privateKey,
            vaultIds: const ['vault-a'],
          )
          .then((result) => expect(result, isFalse));
      clock.flushMicrotasks();
      expect(attempts, 1);
    });
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
