import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/core/widgets/compact_primary_button.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_history_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_history_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_history_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _HistoryService extends Mock implements EntryHistoryService {}

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _HistoryCubit extends EntryHistoryCubit {
  _HistoryCubit(super.service);

  void seed(EntryHistoryState state) => emit(state);
}

void main() {
  late _HistoryCubit cubit;
  late _HistoryService service;
  late _AuthBloc auth;

  final entry = EntryEntity(
    id: 'entry-id',
    vaultId: 'vault-id',
    label: 'Deploy key',
    type: EntryType.key,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    currentRevision: '7',
  );
  final current = EntryHistoryVersion(
    revision: '7',
    changedAt: DateTime.utc(2026, 9, 1, 12, 30),
    changedByType: '1',
    changedById: '11111111-1111-4111-8111-111111111111',
    operation: '2',
    actorName: 'Patryk Roguszewski',
    encrypted: const {'revision': '7'},
  );

  setUp(() {
    service = _HistoryService();
    cubit = _HistoryCubit(service);
    auth = _AuthBloc();
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: const AuthUnauthenticated(),
    );
  });

  tearDown(() async {
    await cubit.close();
    await auth.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<EntryHistoryCubit>.value(value: cubit),
            ],
            child: EntryHistoryTab(entry: entry, onUpdated: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('matches the web history card hierarchy without the warning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    cubit.seed(
      EntryHistoryState(status: EntryHistoryStatus.ready, items: [current]),
    );

    await pump(tester);

    expect(find.text('Version 7'), findsOneWidget);
    expect(find.textContaining('Current ·'), findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.textContaining('Updated ·'), findsNothing);
    expect(find.text('Patryk Roguszewski'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CompactPrimaryButton)).width,
      inInclusiveRange(88, 96),
    );
    expect(tester.getRect(find.text('Reveal')).right, lessThan(355));
    expect(
      tester.getRect(find.text('Patryk Roguszewski')).right,
      greaterThan(330),
    );
    expect(
      tester.getRect(find.textContaining('Current ·')).right,
      lessThan(tester.getRect(find.text('Patryk Roguszewski')).left),
    );
    expect(
      find.text(
        'Historical versions may contain previous passwords and TOTP seeds.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'renders a selected revision as a readable form inside its card',
    (tester) async {
      cubit.seed(
        EntryHistoryState(
          status: EntryHistoryStatus.ready,
          items: [current],
          selectedRevision: current.revision,
          selected: CanonicalEntryHistorySnapshot(
            secret: {
              'entryType': 0,
              'memberLabel': 'Historical deploy key',
              'agentLabel': 'Deploy key',
              'description': 'Used in CI',
              'iconReference': 'vpn_key',
              'agentVisibilityPolicy': {
                'discoverable': true,
                'fields': {'agentLabel': 'discovery'},
              },
            },
            payload: {'value': 'secret-value', 'notes': 'Rotated monthly'},
          ),
        ),
      );

      await pump(tester);

      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Historical deploy key'), findsOneWidget);
      expect(find.text('Entry type'), findsOneWidget);
      expect(find.text('Key'), findsOneWidget);
      expect(find.text('Value'), findsOneWidget);
      expect(find.text('••••••••••••'), findsOneWidget);
      expect(find.text('memberLabel'), findsNothing);
      expect(find.text('Discoverable by organization agents'), findsNothing);
      expect(find.text('Restore this version'), findsNothing);
    },
  );

  testWidgets('disables Load more while pagination is in flight', (
    tester,
  ) async {
    cubit.seed(
      EntryHistoryState(
        status: EntryHistoryStatus.ready,
        items: [current],
        nextCursor: '7',
        loadingMore: true,
      ),
    );

    await pump(tester);

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Load older versions'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('resumes an initial History load canceled in background', (
    tester,
  ) async {
    final stalePage = Completer<EntryHistoryPage>();
    var request = 0;
    when(() => service.loadPage(entry)).thenAnswer((_) {
      if (request++ == 0) return stalePage.future;
      return Future.value(EntryHistoryPage(items: [current], nextCursor: null));
    });
    await pump(tester);

    unawaited(cubit.open(entry));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    verify(() => service.loadPage(entry)).called(2);
    expect(cubit.state.items, [current]);
    stalePage.complete(const EntryHistoryPage(items: [], nextCursor: null));
    await tester.pump();
    expect(cubit.state.items, [current]);
  });

  testWidgets('resume does not open History before the tab requests it', (
    tester,
  ) async {
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    verifyNever(() => service.loadPage(entry));
    expect(cubit.state.status, EntryHistoryStatus.ready);
  });
}
