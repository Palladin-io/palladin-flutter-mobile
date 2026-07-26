import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:mobile_palladin/features/dashboard/domain/repositories/local_search_repository.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_cubit.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_session_controller.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_state.dart';

class MockDashboardRepository extends Mock implements DashboardRepository {}

class MockLocalSearchRepository extends Mock implements LocalSearchRepository {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

const _vault = VaultSearchResult(vaultId: 'v1', displayName: 'Production');
const _entry = EntrySearchResult(
  vaultId: 'v1',
  entryId: 'e1',
  displayName: 'Stripe API Key',
  vaultName: 'Production',
  entryType: 1,
);
const _agent = AgentSearchResult(
  organizationId: 'o1',
  agentId: 'a1',
  displayName: 'Stripe Agent',
);

void main() {
  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(CancelToken());
  });

  late MockDashboardRepository remote;
  late MockLocalSearchRepository local;
  late MockAnalyticsService analytics;
  late SearchSessionController sessions;

  setUp(() {
    remote = MockDashboardRepository();
    local = MockLocalSearchRepository();
    analytics = MockAnalyticsService();
    sessions = SearchSessionController();
    when(
      () => local.search(any(), limit: any(named: 'limit')),
    ).thenReturn(const []);
    when(
      () =>
          analytics.capture(any(), any(), properties: any(named: 'properties')),
    ).thenAnswer((_) async {});
  });

  SearchCubit buildCubit() => SearchCubit(
    repository: remote,
    localRepository: local,
    analytics: analytics,
    sessionController: sessions,
  );

  test('short queries wipe state and never leave the device', () {
    final cubit = buildCubit()..query('a');
    expect(cubit.state, isA<SearchIdle>());
    verifyNever(
      () => remote.globalSearch(
        any(),
        limit: any(named: 'limit'),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
    verifyNever(() => local.search(any(), limit: any(named: 'limit')));
    cubit.close();
  });

  test(
    'publishes local results before remote completes, then appends remote',
    () {
      fakeAsync((async) {
        final pending = Completer<List<SearchResultEntity>>();
        when(
          () => local.search('stripe', limit: 10),
        ).thenReturn(const [_entry]);
        when(
          () => remote.globalSearch(
            'stripe',
            limit: 10,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) => pending.future);
        final cubit = buildCubit()..query('stripe');
        async.elapse(const Duration(milliseconds: 250));
        async.flushMicrotasks();
        expect(cubit.state, isA<SearchResults>());
        expect((cubit.state as SearchResults).results, const [_entry]);
        expect((cubit.state as SearchResults).remotePending, isTrue);

        pending.complete(const [_agent]);
        async.flushMicrotasks();
        expect((cubit.state as SearchResults).results, const [_entry, _agent]);
        cubit.close();
      });
    },
  );

  test('remote failure preserves responsive local results', () {
    fakeAsync((async) {
      when(() => local.search('stripe', limit: 10)).thenReturn(const [_entry]);
      when(
        () => remote.globalSearch(
          'stripe',
          limit: 10,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/search'),
          type: DioExceptionType.connectionError,
        ),
      );
      final cubit = buildCubit()..query('stripe');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      final state = cubit.state as SearchResults;
      expect(state.results, const [_entry]);
      expect(state.remoteFailed, isTrue);
      cubit.close();
    });
  });

  test('new query cancels old transport and stale completion cannot win', () {
    fakeAsync((async) {
      final slow = Completer<List<SearchResultEntity>>();
      final fast = Completer<List<SearchResultEntity>>();
      when(
        () => remote.globalSearch(
          'old',
          limit: 10,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => slow.future);
      when(
        () => remote.globalSearch(
          'new',
          limit: 10,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => fast.future);
      final cubit = buildCubit()..query('old');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      cubit.query('new');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();

      fast.complete(const [_agent]);
      async.flushMicrotasks();
      expect((cubit.state as SearchResults).results, const [_agent]);
      slow.complete(const [_vault]);
      async.flushMicrotasks();
      expect((cubit.state as SearchResults).results, const [_agent]);
      final tokens = verify(
        () => remote.globalSearch(
          any(),
          limit: 10,
          cancelToken: captureAny(named: 'cancelToken'),
        ),
      ).captured.cast<CancelToken>();
      expect(tokens.first.isCancelled, isTrue);
      cubit.close();
    });
  });

  test('security transition wipes results and cancels in-flight query', () {
    fakeAsync((async) {
      final pending = Completer<List<SearchResultEntity>>();
      when(() => local.search('secret', limit: 10)).thenReturn(const [_entry]);
      when(
        () => remote.globalSearch(
          'secret',
          limit: 10,
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) => pending.future);
      final cubit = buildCubit()..query('secret');
      async.elapse(const Duration(milliseconds: 250));
      async.flushMicrotasks();
      expect(cubit.state, isA<SearchResults>());

      sessions.lock();
      expect(cubit.state, isA<SearchIdle>());
      pending.complete(const [_agent]);
      async.flushMicrotasks();
      expect(cubit.state, isA<SearchIdle>());
      cubit.close();
    });
  });

  test('security transition invokes registered view query clearer', () {
    var retainedQuery = 'secret words';
    void clear() => retainedQuery = '';
    sessions.attachView(clear);
    sessions.lock();
    expect(retainedQuery, isEmpty);
    sessions.detachView(clear);
  });

  test('analytics records type only, never query or resource identity', () {
    final cubit = buildCubit();
    cubit.selectResult(_entry);
    verify(
      () => analytics.capture(
        'dashboard',
        'search-result-selected',
        properties: {'type': 'entry'},
      ),
    ).called(1);
    cubit.close();
  });
}
