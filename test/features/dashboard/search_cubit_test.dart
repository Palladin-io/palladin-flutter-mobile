import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_state.dart';

// ──────────────────────────────────────────────
// Mocks & fixtures
// ──────────────────────────────────────────────

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

const _oneResult = SearchResultEntity(
  type: SearchResultType.vault,
  id: 'v1',
  name: 'Production',
);

const _entryResult = SearchResultEntity(
  type: SearchResultType.entry,
  id: 'e1',
  name: 'Stripe API Key',
  vaultId: 'v1',
  vaultName: 'Production',
);

DioException _dioError() => DioException(
      requestOptions: RequestOptions(path: '/api/search'),
      type: DioExceptionType.connectionError,
      error: 'boom',
    );

void main() {
  // Analytics + logger touch platform channels; ensure the binding is up.
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  late MockDashboardRepository repository;
  late MockAnalyticsService analytics;

  setUp(() {
    repository = MockDashboardRepository();
    analytics = MockAnalyticsService();
    when(() => analytics.capture(any(), any(), properties: any(named: 'properties')))
        .thenAnswer((_) async {});
  });

  SearchCubit buildCubit() =>
      SearchCubit(repository: repository, analytics: analytics);

  // ── short queries short-circuit ─────────────

  test('query("") stays idle and never hits the backend', () {
    final cubit = buildCubit();
    cubit.query('');
    expect(cubit.state, isA<SearchIdle>());
    verifyNever(
      () => repository.globalSearch(any(), limit: any(named: 'limit')),
    );
    cubit.close();
  });

  test('query("a") (1 char) stays idle and never hits the backend', () {
    final cubit = buildCubit();
    cubit.query('a');
    expect(cubit.state, isA<SearchIdle>());
    verifyNever(
      () => repository.globalSearch(any(), limit: any(named: 'limit')),
    );
    cubit.close();
  });

  // ── debounced query resolution ──────────────

  test('query("ab") with results emits [Loading, Results]', () {
    fakeAsync((async) {
      when(() => repository.globalSearch('ab', limit: 10))
          .thenAnswer((_) async => const [_oneResult]);

      final cubit = buildCubit();
      final states = <SearchState>[];
      final sub = cubit.stream.listen(states.add);

      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      expect(states, [isA<SearchLoading>(), isA<SearchResults>()]);
      expect((states.last as SearchResults).results, hasLength(1));

      sub.cancel();
      cubit.close();
    });
  });

  test('query("ab") with empty results emits [Loading, Empty]', () {
    fakeAsync((async) {
      when(() => repository.globalSearch('ab', limit: 10))
          .thenAnswer((_) async => const <SearchResultEntity>[]);

      final cubit = buildCubit();
      final states = <SearchState>[];
      final sub = cubit.stream.listen(states.add);

      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      expect(states, [isA<SearchLoading>(), isA<SearchEmpty>()]);

      sub.cancel();
      cubit.close();
    });
  });

  test('query("ab") with a DioException emits [Loading, Error]', () {
    fakeAsync((async) {
      when(() => repository.globalSearch('ab', limit: 10))
          .thenThrow(_dioError());

      final cubit = buildCubit();
      final states = <SearchState>[];
      final sub = cubit.stream.listen(states.add);

      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      expect(states, [isA<SearchLoading>(), isA<SearchError>()]);

      sub.cancel();
      cubit.close();
    });
  });

  // ── debounce coalescing ─────────────────────

  test('rapid-fire queries trigger a single backend call (debounce)', () {
    fakeAsync((async) {
      when(() => repository.globalSearch(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => const [_oneResult]);

      final cubit = buildCubit();

      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 50));
      cubit.query('abc');
      async.elapse(const Duration(milliseconds: 50));
      cubit.query('abcd');
      async.elapse(const Duration(milliseconds: 50));
      cubit.query('abcde');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      verify(() => repository.globalSearch('abcde', limit: 10)).called(1);
      verifyNever(() => repository.globalSearch('ab', limit: 10));
      verifyNever(() => repository.globalSearch('abc', limit: 10));
      verifyNever(() => repository.globalSearch('abcd', limit: 10));

      cubit.close();
    });
  });

  // ── generation guard (stale result drop) ────

  test('a slow earlier query does not overwrite a newer query\'s results', () {
    fakeAsync((async) {
      final slow = Completer<List<SearchResultEntity>>();
      final fast = Completer<List<SearchResultEntity>>();
      when(() => repository.globalSearch('ab', limit: 10))
          .thenAnswer((_) => slow.future);
      when(() => repository.globalSearch('abcd', limit: 10))
          .thenAnswer((_) => fast.future);

      final cubit = buildCubit();

      // First query fires its request (generation 1).
      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250));
      // Second query fires its request (generation 2) before the first resolves.
      cubit.query('abcd');
      async.elapse(const Duration(milliseconds: 250));

      // The newer request resolves first and wins.
      fast.complete(const [_entryResult]);
      async.flushMicrotasks();
      expect((cubit.state as SearchResults).results, [_entryResult]);

      // The older, now-stale request resolves last — must be dropped, not
      // clobber the fresher results.
      slow.complete(const [_oneResult]);
      async.flushMicrotasks();
      expect((cubit.state as SearchResults).results, [_entryResult]);

      cubit.close();
    });
  });

  test('an in-flight query dropped by reset() cannot re-populate results', () {
    fakeAsync((async) {
      final slow = Completer<List<SearchResultEntity>>();
      when(() => repository.globalSearch('ab', limit: 10))
          .thenAnswer((_) => slow.future);

      final cubit = buildCubit();
      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250)); // _run('ab') in flight

      cubit.reset();
      expect(cubit.state, isA<SearchIdle>());

      // The late result must not resurrect a results state after reset().
      slow.complete(const [_oneResult]);
      async.flushMicrotasks();
      expect(cubit.state, isA<SearchIdle>());

      cubit.close();
    });
  });

  // ── reset() ─────────────────────────────────

  test('reset() cancels the pending query and returns to idle', () {
    fakeAsync((async) {
      when(() => repository.globalSearch(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => const [_oneResult]);

      final cubit = buildCubit();
      final states = <SearchState>[];
      final sub = cubit.stream.listen(states.add);

      cubit.query('ab');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      // At this point we have Loading + Results.
      cubit.reset();
      async.flushMicrotasks();

      expect(cubit.state, isA<SearchIdle>());
      expect(states.last, isA<SearchIdle>());

      sub.cancel();
      cubit.close();
    });
  });

  // ── selectResult analytics ──────────────────

  test('selectResult fires analytics with the entry type + id only (ZK)', () {
    final cubit = buildCubit();

    cubit.selectResult(_entryResult);

    verify(
      () => analytics.capture(
        'dashboard',
        'search-result-selected',
        properties: {'type': 'entry', 'id': 'e1'},
      ),
    ).called(1);

    cubit.close();
  });
}
