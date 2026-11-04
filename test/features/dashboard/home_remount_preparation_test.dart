import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_state.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/local_search_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/autofill/data/durable_autofill_repair_coordinator.dart';
import 'package:mobile_palladin/features/autofill/domain/autofill_cache_invalidator.dart';
import 'package:mobile_palladin/features/dashboard/data/repositories/local_search_repository_impl.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_session_controller.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class _Vaults extends Mock implements VaultListCubit {}

class _Index extends Mock
    implements MemberIndexReader, DurableMemberIndexUpdates {}

class _Loader extends Mock implements MemberEntryListLoader {}

class _Local extends Mock implements LocalSearchRepository {}

class _Remote extends Mock implements DashboardRepository {}

class _Analytics extends Mock implements AnalyticsService {}

class _AutoFill extends Mock implements AutoFillPreparedCacheSynchronizer {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  test(
    'direct unlocked replacement clears active views and prepares only the new session',
    () async {
      final views = SearchSessionController();
      final local = _Local();
      final oldKey = Uint8List(32);
      final newKey = Uint8List(32)..[0] = 1;
      final old = Completer<void>();
      final current = Completer<void>();
      when(() => local.prepare(oldKey)).thenAnswer((_) => old.future);
      when(() => local.prepare(newKey)).thenAnswer((_) => current.future);
      final cubit = SearchCubit(
        repository: _Remote(),
        localRepository: local,
        analytics: _Analytics(),
        sessionController: views,
      )..prepare(oldKey, principalId: 'same');
      var cleared = 0;
      views.attachView(() => cleared++);
      final before = AuthAuthenticated(
        userId: 'same',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: oldKey,
      );
      final refresh = before.copyWith(emailVerified: true);
      expect(
        SearchSessionController.replacesUnlockedSession(before, refresh),
        isFalse,
      );
      final after = AuthAuthenticated(
        userId: 'same',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: newKey,
      );
      expect(
        SearchSessionController.replacesUnlockedSession(before, after),
        isTrue,
      );
      views.replaceUnlockedSession(after);
      expect(cleared, greaterThanOrEqualTo(1));
      old.completeError(StateError('old preparation failed'));
      await Future<void>.delayed(Duration.zero);
      current.complete();
      await Future<void>.delayed(Duration.zero);
      cubit.prepare(newKey, principalId: 'same');
      await Future<void>.delayed(Duration.zero);
      verify(() => local.prepare(oldKey)).called(1);
      verify(() => local.prepare(newKey)).called(1);
      final other = AuthAuthenticated(
        userId: 'different',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: newKey,
      );
      expect(
        SearchSessionController.replacesUnlockedSession(after, other),
        isTrue,
      );
      views.replaceUnlockedSession(other);
      await Future<void>.delayed(Duration.zero);
      verify(() => local.prepare(newKey)).called(1);
      await cubit.close();
    },
  );

  test(
    'view preparation clears on lock and an old failure cannot clear the next session',
    () async {
      final views = SearchSessionController();
      final old = Completer<void>();
      final current = Completer<void>();
      var calls = 0;
      final initial = views.prepare('synthetic', () {
        calls++;
        return old.future;
      });
      final rejected = expectLater(initial, throwsStateError);
      views.lock();
      final next = views.prepare('synthetic', () {
        calls++;
        return current.future;
      });
      old.completeError(StateError('old source failure'));
      await rejected;
      expect(
        identical(
          views.prepare('synthetic', () async {
            calls++;
          }),
          next,
        ),
        isTrue,
      );
      current.complete();
      await next;
      await views.prepare('synthetic', () async {
        calls++;
      });
      expect(calls, 2);
      views.lock();
      await views.prepare('synthetic', () async {
        calls++;
      });
      expect(calls, 3);
    },
  );

  test('failed initial view preparation can be retried', () async {
    final views = SearchSessionController();
    var calls = 0;
    await expectLater(
      views.prepare('synthetic', () async {
        calls++;
        throw StateError('source unavailable');
      }),
      throwsStateError,
    );
    await views.prepare('synthetic', () async {
      calls++;
    });
    expect(calls, 2);
  });

  test(
    'Home remount reuses prepared search without a sync or AutoFill publication',
    () async {
      final vaults = _Vaults();
      final index = _Index();
      final loader = _Loader();
      final autoFill = _AutoFill();
      final updates = StreamController<String>.broadcast(sync: true);
      final key = Uint8List(32);
      final session = AutoFillRepairSession(
        principalId: 'synthetic',
        identity: Object(),
        privateKey: key,
      );
      final vault = VaultEntity(
        id: 'vault',
        name: 'Synthetic',
        grantMode: GrantMode.granular,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        entryCount: 0,
        activeGrantCount: 0,
        memberCount: 1,
      );
      when(
        () => vaults.loadForMemberIndex(any(), ensureFresh: false),
      ).thenAnswer((_) async => [vault]);
      when(() => index.durableUpdates).thenAnswer((_) => updates.stream);
      when(() => index.waitForCurrent(any())).thenAnswer((_) async {});
      var syncs = 0;
      var publications = 0;
      when(
        () => loader.load(
          vaultId: any(named: 'vaultId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) async {
        syncs++;
        // Real MemberSync publishes this signal after even an empty delta commit.
        updates.add('vault');
        return [];
      });
      when(
        () => autoFill.synchronizePrepared(
          privateKey: any(named: 'privateKey'),
          vaultIds: any(named: 'vaultIds'),
        ),
      ).thenAnswer((_) async {
        publications++;
      });
      final coordinator = DurableAutoFillRepairCoordinator(
        memberIndexes: index,
        autoFill: autoFill,
        currentSession: () => session,
      )..start();
      coordinator.replaceKnownVaults(['vault']);
      final local = LocalSearchRepositoryImpl(
        vaults: vaults,
        memberIndex: index,
        entryLoader: loader,
      );
      final views = SearchSessionController();
      SearchCubit mount() => SearchCubit(
        repository: _Remote(),
        localRepository: local,
        analytics: _Analytics(),
        sessionController: views,
      )..prepare(key, principalId: 'synthetic');
      final first = mount();
      await Future<void>.delayed(Duration.zero);
      await coordinator.drainPending();
      await first.close();
      final remounted = mount();
      await Future<void>.delayed(Duration.zero);
      await coordinator.drainPending();
      await remounted.close();
      expect(syncs, 1);
      expect(publications, 1);
      // Real app lifecycle/mutation preparation bypasses view deduplication.
      await local.prepare(key);
      expect(syncs, 2);
      await coordinator.drainPending();
      expect(publications, 2);
      await coordinator.dispose();
      await updates.close();
    },
  );
}
