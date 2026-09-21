import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_sharing_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_sharing_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Remote extends Mock implements EntrySharingRemoteDatasource {}

class _Authority extends Mock implements MemberSyncSessionAuthorityProvider {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _session = (
  principalId: 'member',
  organizationId: 'org',
  authorizationGeneration: '1',
  keyGeneration: 0,
);
const _shareId = '00112233-4455-4677-8899-aabbccddeeff';
Map<String, Object?> _wire({String status = 'active'}) => {
  'shareId': _shareId,
  'status': status,
  'expiresAt': '2026-09-22T12:00:00.123456789Z',
  'maximumReceipts': 3,
  'deliveryCount': 1,
  'firstDeliveredAt': '2026-09-20T12:00:00Z',
  'lastDeliveredAt': '2026-09-20T12:00:00Z',
  'firstConfirmedAt': null,
  'notifyOnFirstReceipt': true,
  'recipientMode': 'namedRecipient',
  'recipientEmail': 'recipient@example.test',
  'protection': 'pin',
  'sourceChanged': true,
};
EntryShareListItem _item({String status = 'active', String id = _shareId}) =>
    EntryShareListItem(
      shareId: id,
      status: status,
      expiresAt: DateTime.utc(2026, 9, 22),
      maximumReceipts: 3,
      deliveryCount: 1,
      firstDeliveredAt: DateTime.utc(2026, 9, 20),
      lastDeliveredAt: DateTime.utc(2026, 9, 20),
      firstConfirmedAt: null,
      notifyOnFirstReceipt: true,
      recipientMode: 'namedRecipient',
      recipientEmail: 'recipient@example.test',
      protection: 'pin',
      sourceChanged: true,
    );
EntrySharesPage _page({String? cursor, String status = 'active'}) =>
    EntrySharesPage(
      items: [_item(status: status)],
      nextCursor: cursor,
    );

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});
  String body;
  int status;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => registerFallbackValue(CancelToken()));

  group('sender transport', () {
    test(
      'uses scoped route, cursor, no-store, no redirects and preserves future statuses',
      () async {
        final adapter = _Adapter(
          jsonEncode({
            'items': [
              {..._wire(status: 'future'), 'extra': true},
            ],
            'nextCursor': 'next',
            'new': 1,
          }),
        );
        final api = EntrySharingRemoteDatasource(
          Dio()..httpClientAdapter = adapter,
        );
        final token = CancelToken();
        final page = await api.list(
          'vault/1',
          'entry/1',
          cursor: 'opaque',
          cancelToken: token,
        );
        expect(page.items.single.status, 'future');
        expect(page.items.single.canRevoke, false);
        expect(page.nextCursor, 'next');
        final request = adapter.requests.single;
        expect(request.path, '/api/vaults/vault%2F1/entries/entry%2F1/sharing');
        expect(request.queryParameters, {'cursor': 'opaque'});
        expect(request.headers['Cache-Control'], 'no-store');
        expect(request.followRedirects, false);
        expect(request.data, null);
        expect(request.responseType, ResponseType.plain);
      },
    );
    test(
      'missing display timestamps and future protection do not collapse the list',
      () async {
        final adapter = _Adapter(
          jsonEncode({
            'items': [
              {
                ..._wire(),
                'expiresAt': 'not-a-date',
                'firstDeliveredAt': null,
                'protection': 'future',
              },
            ],
            'nextCursor': null,
          }),
        );
        final page = await EntrySharingRemoteDatasource(
          Dio()..httpClientAdapter = adapter,
        ).list('v', 'e', cancelToken: CancelToken());
        expect(page.items, hasLength(1));
        expect(page.items.single.expiresAt, null);
        expect(page.items.single.protection, 'future');
      },
    );
    test('delete sends only the selected route and no body', () async {
      final adapter = _Adapter('', status: 204);
      await EntrySharingRemoteDatasource(
        Dio()..httpClientAdapter = adapter,
      ).revoke('v', 'e', 's/1', cancelToken: CancelToken());
      expect(adapter.requests.single.method, 'DELETE');
      expect(
        adapter.requests.single.path,
        '/api/vaults/v/entries/e/sharing/s%2F1',
      );
      expect(adapter.requests.single.data, null);
    });
    test(
      'HTTP and JSON errors expose neither body nor request diagnostics',
      () async {
        for (final status in [200, 403, 500]) {
          final adapter = _Adapter(
            'synthetic-private-response',
            status: status,
          );
          final api = EntrySharingRemoteDatasource(
            Dio()..httpClientAdapter = adapter,
          );
          await expectLater(
            api.list('v', 'e', cancelToken: CancelToken()),
            throwsA(
              isA<EntrySharingRequestException>().having(
                (error) => error.toString(),
                'safe error',
                'EntrySharingRequestException',
              ),
            ),
          );
          expect(adapter.requests, hasLength(1));
        }
      },
    );
  });

  group('list ownership', () {
    late _Remote remote;
    late EntrySharingCubit cubit;
    EntrySharingSession? session;
    setUp(() {
      remote = _Remote();
      session = _session;
      when(
        () => remote.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => _page(cursor: 'next'));
      when(
        () => remote.revoke(
          any(),
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {});
      cubit = EntrySharingCubit(
        remote: remote,
        vaultId: 'v',
        entryId: 'e',
        sessionReader: () async => session,
      );
    });
    tearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    for (final revoke in [false, true]) {
      test(
        'failed request cannot restore metadata after organization change (revoke=$revoke)',
        () async {
          await cubit.load();
          final pending = Completer<EntrySharesPage>();
          if (revoke) {
            when(
              () => remote.revoke(
                any(),
                any(),
                any(),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).thenAnswer((_) async {
              await pending.future;
            });
          } else {
            when(
              () => remote.list(
                any(),
                any(),
                cursor: any(named: 'cursor'),
                cancelToken: any(named: 'cancelToken'),
              ),
            ).thenAnswer((_) => pending.future);
          }
          final request = revoke ? cubit.revoke(_shareId) : cubit.load();
          await Future<void>.delayed(Duration.zero);
          session = (
            principalId: 'member',
            organizationId: 'other',
            authorizationGeneration: '1',
            keyGeneration: 0,
          );
          pending.completeError(const EntrySharingRequestException());
          await request;
          expect(cubit.state.items, isEmpty);
          expect(cubit.state.failure, EntrySharingFailure.unavailable);
        },
      );
    }

    test(
      'does not request before explicit load and serializes double taps',
      () async {
        verifyNever(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await Future.wait([cubit.load(), cubit.load()]);
        expect(cubit.state.items, hasLength(1));
        verify(
          () => remote.list(
            'v',
            'e',
            cursor: null,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      },
    );
    test('loads next page without duplicating the same share', () async {
      await cubit.load();
      await cubit.load(more: true);
      expect(cubit.state.items, hasLength(1));
      verify(
        () => remote.list(
          'v',
          'e',
          cursor: 'next',
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    });
    test(
      'clear cancels in-flight transport and discards late completion',
      () async {
        final pending = Completer<EntrySharesPage>();
        CancelToken? token;
        when(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((call) {
          token = call.namedArguments[#cancelToken] as CancelToken;
          return pending.future;
        });
        final load = cubit.load();
        await Future<void>.delayed(Duration.zero);
        cubit.clear();
        expect(token!.isCancelled, true);
        pending.complete(_page());
        await load;
        expect(cubit.state.items, isEmpty);
        expect(cubit.state.loaded, false);
      },
    );
    for (final changed in [
      (
        principalId: 'other',
        organizationId: 'org',
        authorizationGeneration: '1',
        keyGeneration: 0,
      ),
      (
        principalId: 'member',
        organizationId: 'other',
        authorizationGeneration: '1',
        keyGeneration: 0,
      ),
      (
        principalId: 'member',
        organizationId: 'org',
        authorizationGeneration: '2',
        keyGeneration: 0,
      ),
      (
        principalId: 'member',
        organizationId: 'org',
        authorizationGeneration: '1',
        keyGeneration: 1,
      ),
    ]) {
      test('session replacement cannot mutate old shares: $changed', () async {
        await cubit.load();
        session = changed;
        expect(await cubit.revoke(_shareId), false);
        expect(cubit.state.failure, EntrySharingFailure.unavailable);
        expect(cubit.state.items, isEmpty);
        verifyNever(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await cubit.load();
        expect(cubit.state.items, isEmpty);
      });
    }
    test(
      'no session prevents loading and same-session refresh is allowed',
      () async {
        session = null;
        await cubit.load();
        expect(cubit.state.failure, EntrySharingFailure.unavailable);
        verifyNever(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        session = _session;
        await cubit.load();
        expect(cubit.state.items, hasLength(1));
      },
    );
    test(
      'failed load-more preserves rows and cursor for explicit retry',
      () async {
        await cubit.load();
        when(
          () => remote.list(
            'v',
            'e',
            cursor: 'next',
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(const EntrySharingRequestException());
        await cubit.load(more: true);
        expect(cubit.state.items, hasLength(1));
        expect(cubit.state.nextCursor, 'next');
        expect(cubit.state.failure, EntrySharingFailure.loadMore);
      },
    );
    test(
      'only known revocable rows can be revoked; success reloads authority',
      () async {
        await cubit.load();
        expect(await cubit.revoke('unknown'), false);
        when(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => _page(status: 'revoked'));
        expect(await cubit.revoke(_shareId), true);
        expect(cubit.state.items.single.status, 'revoked');
        expect(await cubit.revoke(_shareId), false);
        verify(
          () => remote.revoke(
            'v',
            'e',
            _shareId,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      },
    );
    test(
      'late revoke after disposal cannot report success or reload',
      () async {
        await cubit.load();
        final pending = Completer<void>();
        when(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) => pending.future);
        final result = cubit.revoke(_shareId);
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
        pending.complete();
        expect(await result, false);
        verify(
          () => remote.list(
            'v',
            'e',
            cursor: null,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
      },
    );
    test(
      'failed revoke preserves data and exposes a typed retryable failure',
      () async {
        await cubit.load();
        when(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(StateError('private diagnostics'));
        expect(await cubit.revoke(_shareId), false);
        expect(cubit.state.items, hasLength(1));
        expect(cubit.state.failure, EntrySharingFailure.revoke);
      },
    );
  });

  group('mobile surface', () {
    late _Remote remote;
    late _Auth auth;
    late StreamController<AuthState> authEvents;
    late AuthAuthenticated unlocked;
    final entry = EntryEntity(
      id: 'e',
      vaultId: 'v',
      label: 'Synthetic entry',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      currentRevision: '1',
    );
    setUp(() {
      remote = _Remote();
      auth = _Auth();
      authEvents = StreamController<AuthState>();
      unlocked = AuthAuthenticated(
        userId: 'member',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
        permissions: 8,
      );
      whenListen(auth, authEvents.stream, initialState: unlocked);
      when(
        () => remote.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => _page());
      when(
        () => remote.revoke(
          any(),
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {});
      final authority = _Authority();
      when(authority.current).thenAnswer(
        (_) async => const MemberSyncSessionAuthority(
          principalId: 'member',
          organizationId: 'org',
          organizationMembershipGeneration: '1',
          offlinePolicy: '1h',
          offlinePolicyVersion: 1,
        ),
      );
      getIt.registerSingleton<EntrySharingRemoteDatasource>(remote);
      getIt.registerSingleton<MemberSyncSessionAuthorityProvider>(authority);
      getIt.registerSingleton<VaultSessionStore>(VaultSessionStore());
    });
    tearDown(() async {
      await authEvents.close();
      await auth.close();
      await getIt.reset();
    });
    Future<void> pump(
      WidgetTester tester, {
      bool active = true,
      String locale = 'en',
      Brightness brightness = Brightness.light,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<AuthBloc>.value(
            value: auth,
            child: Scaffold(
              body: EntrySharingTab(entry: entry, active: active),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets(
      'error state offers explicit retry and recovers without losing scope',
      (tester) async {
        when(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(const EntrySharingRequestException());
        await pump(tester);
        expect(find.text('Could not load sharing links.'), findsOneWidget);
        when(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => _page());
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('recipient@example.test'), findsOneWidget);
        await dispose(tester);
      },
    );

    testWidgets(
      'unknown server state remains visible without a guessed revoke action',
      (tester) async {
        when(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => _page(status: 'future'));
        await pump(tester);
        expect(find.text('recipient@example.test'), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        expect(find.text('Revoke link'), findsNothing);
        await dispose(tester);
      },
    );

    testWidgets(
      'Polish dark UI and confirmation fit a narrow enlarged-text viewport',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(
          tester,
          locale: 'pl',
          brightness: Brightness.dark,
          textScale: 1.5,
        );
        await tester.ensureVisible(find.text('Odwołaj link'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Odwołaj link'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Nie usunie pobranych kopii'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
        await tester.tap(find.text('Anuluj'));
        await tester.pumpAndSettle();
        await dispose(tester);
      },
    );

    testWidgets(
      'renders receipt vs confirmation, PIN and notification in a narrow layout',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(tester);
        expect(find.text('First delivery'), findsOneWidget);
        expect(find.text('First display confirmation'), findsOneWidget);
        expect(find.text('PIN'), findsOneWidget);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.textContaining('one Inbox notification'), findsOneWidget);
        expect(tester.takeException(), null);
        await dispose(tester);
      },
    );
    testWidgets(
      'inactive tab does not load; hiding cancels polling and clears rows',
      (tester) async {
        await pump(tester, active: false);
        verifyNever(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await pump(tester);
        expect(find.text('recipient@example.test'), findsOneWidget);
        await pump(tester, active: false);
        expect(find.text('recipient@example.test'), findsNothing);
        await tester.pump(const Duration(seconds: 31));
        verify(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        await dispose(tester);
      },
    );
    testWidgets('foreground polls; background clears and resume reloads', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      verify(
        () => remote.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('recipient@example.test'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 31));
      verifyNever(
        () => remote.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('recipient@example.test'), findsOneWidget);
      await dispose(tester);
    });
    testWidgets(
      'lock clears metadata and prevents restart under a new account',
      (tester) async {
        await pump(tester);
        authEvents.add(unlocked.copyWith(clearKeys: true, isVaultLocked: true));
        await tester.pumpAndSettle();
        expect(find.text('recipient@example.test'), findsNothing);
        expect(find.textContaining('Reopen the entry'), findsOneWidget);
        authEvents.add(unlocked.copyWith(userId: 'other'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 31));
        verify(
          () => remote.list(
            any(),
            any(),
            cursor: any(named: 'cursor'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        await dispose(tester);
      },
    );
    testWidgets(
      'revoke requires confirmation; cancel never mutates; Polish copy is localized',
      (tester) async {
        await pump(tester, locale: 'pl');
        await tester.ensureVisible(find.text('Odwołaj link'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Odwołaj link'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Nie usunie pobranych kopii'),
          findsOneWidget,
        );
        verifyNever(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await tester.tap(find.text('Anuluj'));
        await tester.pumpAndSettle();
        verifyNever(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await tester.tap(find.text('Odwołaj link'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Odwołaj link'));
        await tester.pumpAndSettle();
        verify(
          () => remote.revoke(
            'v',
            'e',
            _shareId,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        expect(find.text('Link udostępniania odwołany.'), findsOneWidget);
        await dispose(tester);
      },
    );
    testWidgets(
      'locking an open confirmation sheet dismisses it without revoking',
      (tester) async {
        await pump(tester);
        await tester.ensureVisible(find.text('Revoke link'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Revoke link'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('It cannot remove downloaded copies'),
          findsOneWidget,
        );
        authEvents.add(unlocked.copyWith(clearKeys: true, isVaultLocked: true));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('It cannot remove downloaded copies'),
          findsNothing,
        );
        verifyNever(
          () => remote.revoke(
            any(),
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
        await dispose(tester);
      },
    );
  });
}
