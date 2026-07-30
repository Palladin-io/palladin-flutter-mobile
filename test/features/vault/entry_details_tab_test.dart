import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_details_tab.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';

class _MockEntryRepository extends Mock implements EntryRepository {}

class _MockCanonicalService extends Mock
    implements CanonicalEntryDetailService {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

EntryEntity _keyEntry() => EntryEntity(
  id: 'e1',
  vaultId: 'v1',
  label: 'Deploy key',
  type: EntryType.key,
  createdAt: DateTime.utc(2026, 6, 1),
  updatedAt: DateTime.utc(2026, 6, 2),
);

void main() {
  const secret = 'sk_live_supersecret';

  AuthAuthenticated unlockedAuth() => AuthAuthenticated(
    userId: 'u1',
    isOnboarded: true,
    isVaultLocked: false,
    privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
  );

  _MockAuthBloc authBloc(AuthState state) {
    final bloc = _MockAuthBloc();
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: state);
    return bloc;
  }

  setUpAll(() {
    registerFallbackValue(_keyEntry());
    registerFallbackValue(EntryType.key);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      AgentVisibilityPolicy(discoverable: false, fields: const {}),
    );
    registerFallbackValue(
      CanonicalEntrySnapshot(entry: {}, payload: {}, secret: {}),
    );
  });

  Future<({EditEntryCubit cubit, _MockCanonicalService canonical})> pumpTab(
    WidgetTester tester, {
    required EntryEntity entry,
    required Map<String, dynamic> payload,
  }) async {
    final canonical = _MockCanonicalService();
    when(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => CanonicalEntrySnapshot(
        entry: {'currentRevision': '1'},
        payload: Map<String, dynamic>.from(payload),
        secret: {
          'schemaVersion': 1,
          'agentLabel': entry.label,
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {
              'agentLabel': 'discovery',
              if (entry.type == EntryType.credential) ...{
                'username': 'discovery',
                'urlDomain': 'never',
              },
            },
          },
        },
      ),
    );
    final cubit = EditEntryCubit(
      repository: _MockEntryRepository(),
      canonicalService: canonical,
    );
    await cubit.revealForEdit(
      entry: entry,
      privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
    );
    addTearDown(cubit.close);
    final auth = authBloc(unlockedAuth());

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<EditEntryCubit>.value(value: cubit),
            ],
            child: EntryDetailsTab(
              entry: entry,
              onUpdated: (_) {},
              onDeleted: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (cubit: cubit, canonical: canonical);
  }

  Future<void> enterEdit(WidgetTester tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.entryEditAction));
    await tester.pump();
  }

  testWidgets('loads canonical details on entry without a reveal gate', (
    tester,
  ) async {
    final canonical = _MockCanonicalService();
    final cubit = EditEntryCubit(
      repository: _MockEntryRepository(),
      canonicalService: canonical,
    );
    when(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => CanonicalEntrySnapshot(
        entry: {'currentRevision': '1'},
        payload: {'value': secret},
        secret: {'schemaVersion': 1},
      ),
    );
    addTearDown(cubit.close);
    final auth = authBloc(unlockedAuth());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<EditEntryCubit>.value(value: cubit),
            ],
            child: EntryDetailsTab(
              entry: _keyEntry(),
              onUpdated: (_) {},
              onDeleted: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.entryRevealDetailsAction), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.entryEditAction), findsOneWidget);
    expect(find.text(secret), findsNothing);
    verify(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
  });

  testWidgets('read-only secret is masked and can be revealed per field', (
    tester,
  ) async {
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});

    expect(find.text(secret), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text(secret), findsOneWidget);
  });

  testWidgets('Details opens read-only and Edit switches to the form', (
    tester,
  ) async {
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.entryEditAction), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-edit-footer')), findsOneWidget);
    await enterEdit(tester);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text(l10n.entrySaveAction), findsOneWidget);
    expect(find.text(l10n.entryDangerZone), findsOneWidget);
  });

  testWidgets('successful save refreshes the canonical base for another edit', (
    tester,
  ) async {
    final harness = await pumpTab(
      tester,
      entry: _keyEntry(),
      payload: {'value': secret},
    );
    when(
      () => harness.canonical.update(
        snapshot: any(named: 'snapshot'),
        expected: any(named: 'expected'),
        label: any(named: 'label'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        type: any(named: 'type'),
        content: any(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
        agentLabel: any(named: 'agentLabel'),
      ),
    ).thenAnswer(
      (_) async => EntryEntity(
        id: 'e1',
        vaultId: 'v1',
        label: 'Deploy key updated',
        type: EntryType.key,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 7, 30),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await enterEdit(tester);
    final save = find.text(l10n.entrySaveAction);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('entry-edit-footer')), findsOneWidget);
    expect(find.text(l10n.entryChangesSaved), findsOneWidget);
    expect(harness.cubit.hasCanonicalSnapshot, isTrue);
    verify(
      () => harness.canonical.update(
        snapshot: any(named: 'snapshot'),
        expected: any(named: 'expected'),
        label: any(named: 'label'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        type: any(named: 'type'),
        content: any(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
        agentLabel: any(named: 'agentLabel'),
      ),
    ).called(1);
  });

  testWidgets('failed save keeps the populated form and its values', (
    tester,
  ) async {
    final harness = await pumpTab(
      tester,
      entry: _keyEntry(),
      payload: {'value': secret},
    );
    when(
      () => harness.canonical.update(
        snapshot: any(named: 'snapshot'),
        expected: any(named: 'expected'),
        label: any(named: 'label'),
        description: any(named: 'description'),
        icon: any(named: 'icon'),
        type: any(named: 'type'),
        content: any(named: 'content'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
        agentLabel: any(named: 'agentLabel'),
      ),
    ).thenThrow(
      const CanonicalEntryDetailException(CanonicalEntryDetailError.network),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await enterEdit(tester);
    await tester.tap(find.text(l10n.entrySaveAction));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('entry-save-footer')), findsOneWidget);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .where((field) => field.controller.text == secret),
      isNotEmpty,
    );
  });

  testWidgets('keeps Save Changes in a sticky footer while content scrolls', (
    tester,
  ) async {
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await enterEdit(tester);

    expect(find.byKey(const ValueKey('entry-save-footer')), findsOneWidget);
    expect(find.text(l10n.entrySaveAction), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('entry-save-footer')), findsOneWidget);
    expect(find.text(l10n.entrySaveAction), findsOneWidget);
  });

  testWidgets('shows field-level discovery controls without technical labels', (
    tester,
  ) async {
    final entry = EntryEntity(
      id: 'e2',
      vaultId: 'v1',
      label: 'Account',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 2),
    );
    await pumpTab(
      tester,
      entry: entry,
      payload: {'username': 'user', 'password': 'secret', 'url': 'example.com'},
    );
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
    await enterEdit(tester);

    expect(
      find.byKey(const ValueKey('entry-discovery-agentLabel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entry-discovery-description')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entry-discovery-username')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('entry-discovery-urlDomain')),
      findsOneWidget,
    );
    expect(find.textContaining('urlDomain'), findsNothing);
    expect(find.textContaining('Grant:'), findsNothing);
  });

  testWidgets('multiline values show three lines with an explicit expander', (
    tester,
  ) async {
    final multiline = List.generate(8, (index) => 'line $index').join('\n');
    await pumpTab(
      tester,
      entry: _keyEntry(),
      payload: {
        'value': secret,
        'fields': [
          {
            'id': 'notes-field',
            'label': 'Runbook',
            'type': 'multiline',
            'value': multiline,
            'agentVisible': true,
          },
        ],
      },
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.entryShowMore), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);

    await tester.tap(find.text(l10n.entryShowMore));
    await tester.pump();
    expect(find.text(l10n.entryShowLess), findsOneWidget);
  });

  testWidgets('background transition drops decrypted and revealed state', (
    tester,
  ) async {
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});
    expect(find.text(secret), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .where((field) => field.controller.text == secret),
      isEmpty,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(secret), findsNothing);
    expect(find.byKey(const ValueKey('entry-edit-footer')), findsOneWidget);
  });
}
