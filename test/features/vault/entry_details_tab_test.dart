import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/core/widgets/app_toggle.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_widgets.dart';
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
    Map<String, String> fieldAccess = const {},
    String? savedAgentLabel,
    EntryEditController? editController,
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
          'agentLabel': savedAgentLabel ?? entry.label,
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {
              'agentLabel': 'discovery',
              if (entry.type == EntryType.credential) ...{
                'username': 'discovery',
                'urlDomain': 'never',
              },
              ...fieldAccess,
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
              editController: editController,
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

  for (final bottomInset in [24.0, 48.0]) {
    testWidgets('Edit and Save clear a $bottomInset px system navigation bar', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.reset);
      await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final edit = find.widgetWithText(ElevatedButton, l10n.entryEditAction);
      expect(
        tester.getBottomRight(edit).dy,
        lessThanOrEqualTo(844 - bottomInset),
      );
      await enterEdit(tester);
      final save = find.widgetWithText(ElevatedButton, l10n.entrySaveAction);
      expect(
        tester.getBottomRight(save).dy,
        lessThanOrEqualTo(844 - bottomInset),
      );
    });
  }

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

  testWidgets('applying TOTP saves the canonical entry without a second Save', (
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
    final addTotp = find.text(l10n.totpAdd);
    await tester.ensureVisible(addTotp);
    await tester.tap(addTotp);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(TextField)).first,
      'JBSWY3DPEHPK3PXP',
    );
    await tester.tap(
      find.descendant(of: sheet, matching: find.text(l10n.entrySaveAction)),
    );
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
        content: any(
          named: 'content',
          that: predicate<Map<String, dynamic>>(
            (payload) =>
                ((payload['fields'] as List).single['value']
                    as Map)['secret'] ==
                'JBSWY3DPEHPK3PXP',
          ),
        ),
        memberPrivateKey: any(named: 'memberPrivateKey'),
        agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
        agentLabel: any(named: 'agentLabel'),
      ),
    ).called(1);
  });

  testWidgets(
    'TOTP conflict keeps the draft and requires confirmation before replacing the latest revision',
    (tester) async {
      final harness = await pumpTab(
        tester,
        entry: _keyEntry(),
        payload: {'value': secret},
      );
      var attempts = 0;
      final baseRevisions = <String>[];
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
      ).thenAnswer((invocation) async {
        expect(invocation.namedArguments[#label], 'Local draft');
        expect((invocation.namedArguments[#content] as Map)['value'], secret);
        baseRevisions.add(
          (invocation.namedArguments[#snapshot] as CanonicalEntrySnapshot)
                  .entry['currentRevision']
              as String,
        );
        if (attempts++ == 0) {
          throw const CanonicalEntryDetailException(
            CanonicalEntryDetailError.conflict,
          );
        }
        return EntryEntity(
          id: 'e1',
          vaultId: 'v1',
          label: 'Deploy key updated',
          type: EntryType.key,
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: DateTime.utc(2026, 7, 30),
        );
      });

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await enterEdit(tester);
      await tester.enterText(find.byType(TextField).first, 'Local draft');
      final addTotp = find.text(l10n.totpAdd);
      await tester.ensureVisible(addTotp);
      await tester.tap(addTotp);
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      await tester.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)).first,
        'JBSWY3DPEHPK3PXP',
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text(l10n.entrySaveAction)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('entry-save-footer')), findsOneWidget);
      expect(harness.cubit.state, isA<EditEntryConflict>());
      expect(find.text(l10n.totpAdd), findsNothing);
      final save = find.text(l10n.entrySaveAction);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l10n.vaultCancel));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(harness.cubit.state, isA<EditEntryConflict>());
      when(
        () => harness.canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) async {
        if (attempts == 1) {
          expect(
            (invocation.namedArguments[#expected] as EntryEntity)
                .currentRevision,
            EntryEntity.unspecifiedRevision,
          );
        }
        return CanonicalEntrySnapshot(
          entry: {'currentRevision': '2'},
          payload: {'value': 'remote-value'},
          secret: {},
        );
      });
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.entrySaveAction),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('entry-edit-footer')), findsOneWidget);
      expect(find.text(l10n.entryChangesSaved), findsOneWidget);
      expect(harness.cubit.hasCanonicalSnapshot, isTrue);
      expect(baseRevisions, ['1', '2']);
      verify(
        () => harness.canonical.update(
          snapshot: any(named: 'snapshot'),
          expected: any(named: 'expected'),
          label: any(named: 'label'),
          description: any(named: 'description'),
          icon: any(named: 'icon'),
          type: any(named: 'type'),
          content: any(
            named: 'content',
            that: predicate<Map<String, dynamic>>(
              (payload) =>
                  ((payload['fields'] as List).single['value']
                      as Map)['secret'] ==
                  'JBSWY3DPEHPK3PXP',
            ),
          ),
          memberPrivateKey: any(named: 'memberPrivateKey'),
          agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
          agentLabel: any(named: 'agentLabel'),
        ),
      ).called(2);
    },
  );

  testWidgets('repeated save taps start only one canonical mutation', (
    tester,
  ) async {
    final harness = await pumpTab(
      tester,
      entry: _keyEntry(),
      payload: {'value': secret},
    );
    final completion = Completer<EntryEntity>();
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
    ).thenAnswer((_) => completion.future);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await enterEdit(tester);
    final save = find.text(l10n.entrySaveAction);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();

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

    completion.complete(
      EntryEntity(
        id: 'e1',
        vaultId: 'v1',
        label: 'Deploy key',
        type: EntryType.key,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 7, 30),
        currentRevision: '2',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryChangesSaved), findsOneWidget);
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

  group('sign-in method', () {
    final credential = EntryEntity(
      id: 'e3',
      vaultId: 'v1',
      label: 'Example',
      type: EntryType.credential,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 2),
    );

    Map<String, dynamic> payloadWith(List<Map<String, dynamic>> fields) => {
      'username': 'qa@example.test',
      'password': '',
      'url': 'https://example.test',
      'fields': fields,
    };

    Map<String, dynamic> binding(
      Object? value, {
      String id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    }) => {
      'id': id,
      'label': 'Sign-in method',
      'type': 'palladin.signin.v1',
      'value': value,
    };

    Future<String> rowText(WidgetTester tester) async {
      final row = find.byKey(const ValueKey('entry-sign-in-method'));
      expect(row, findsOneWidget);
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>();
      return texts.where((text) => text != 'Sign-in methods').join(' · ');
    }

    const legacyId = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
    const ordinaryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    const opaqueId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    const collectionId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    const totpId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    final interleaved = <Map<String, dynamic>>[
      {
        'id': legacyId,
        'label': 'Legacy',
        'type': 'palladin.signin.v1',
        'value': {
          'provider': 'google',
          'account': 'legacy@example.test',
          'entry': null,
        },
      },
      {
        'id': ordinaryId,
        'label': 'Team',
        'type': 'text',
        'value': 'Operations',
      },
      {
        'id': opaqueId,
        'label': 'Opaque',
        'type': 'future.v9',
        'value': {
          'keep': ['byte', 'equivalent'],
        },
      },
      {
        'id': collectionId,
        'label': 'Github',
        'type': 'palladin.signin.v2',
        'value': {'provider': 'github', 'account': 'octo', 'entry': null},
      },
      {
        'id': totpId,
        'label': 'Authenticator',
        'type': 'totp',
        'value': {
          'secret': 'JBSWY3DPEHPK3PXP',
          'algorithm': 'SHA1',
          'digits': 6,
          'period': 30,
          'issuer': null,
          'account': null,
        },
      },
    ];
    final interleavedAccess = <String, String>{
      legacyId: 'never',
      ordinaryId: 'onGrantValue',
      opaqueId: 'never',
      collectionId: 'discovery',
      totpId: 'never',
    };

    List<
      ({
        Map<String, dynamic> content,
        AgentVisibilityPolicy? policy,
        String? agentLabel,
      })
    >
    recordSaves(_MockCanonicalService canonical) {
      final saves =
          <
            ({
              Map<String, dynamic> content,
              AgentVisibilityPolicy? policy,
              String? agentLabel,
            })
          >[];
      when(
        () => canonical.update(
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
      ).thenAnswer((invocation) async {
        saves.add((
          content: Map<String, dynamic>.from(
            invocation.namedArguments[#content] as Map,
          ),
          policy:
              invocation.namedArguments[#agentVisibilityPolicy]
                  as AgentVisibilityPolicy?,
          agentLabel: invocation.namedArguments[#agentLabel] as String?,
        ));
        return credential;
      });
      return saves;
    }

    Future<void> openMethod(WidgetTester tester, String id) async {
      final edit = find.byKey(ValueKey('sign-in-method-edit-$id'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }

    Future<void> saveSheet(WidgetTester tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(l10n.entrySaveAction),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> saveForm(WidgetTester tester) async {
      final footer = find.byKey(const ValueKey('entry-save-footer'));
      await tester.tap(
        find.descendant(of: footer, matching: find.byType(EntrySaveButton)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'canceling method visibility restores saved policy before an unrelated save',
      (tester) async {
        final controller = EntryEditController();
        addTearDown(controller.dispose);
        final harness = await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith([interleaved.first]),
          fieldAccess: {legacyId: 'never'},
          savedAgentLabel: 'Saved agent label',
          editController: controller,
        );
        final saves = recordSaves(harness.canonical);
        await enterEdit(tester);
        await openMethod(tester, legacyId);
        await tester.tap(find.byType(AppToggle));
        await saveSheet(tester);
        controller.requestCancel();
        await tester.pumpAndSettle();
        await enterEdit(tester);
        await tester.enterText(
          find.byType(TextField).first,
          'Unrelated rename',
        );
        await saveForm(tester);
        expect(saves, hasLength(1));
        expect(saves.single.policy?.fields[legacyId], AgentFieldAccess.never);
        expect(saves.single.agentLabel, 'Saved agent label');
        expect(
          (saves.single.content['fields'] as List).single,
          interleaved.first,
        );
      },
    );

    testWidgets(
      'unrelated form save retains original interleaved custom field order',
      (tester) async {
        final harness = await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith(interleaved),
          fieldAccess: interleavedAccess,
        );
        final saves = recordSaves(harness.canonical);
        await enterEdit(tester);
        await tester.enterText(
          find.byType(TextField).first,
          'Unrelated rename',
        );
        await saveForm(tester);
        expect(saves, hasLength(1));
        expect(saves.single.content['fields'], interleaved);
        for (final access in interleavedAccess.entries) {
          expect(
            saves.single.policy?.fields[access.key]?.wireName,
            access.value,
          );
        }
      },
    );

    testWidgets(
      'explicit ordinary field reordering keeps opaque and method slots anchored',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const otherId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        final other = {
          'id': otherId,
          'label': 'Second',
          'type': 'text',
          'value': 'Second value',
        };
        final harness = await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith([...interleaved, other]),
          fieldAccess: {...interleavedAccess, otherId: 'never'},
        );
        final saves = recordSaves(harness.canonical);
        await enterEdit(tester);
        final row = find
            .ancestor(
              of: find.widgetWithText(TextField, 'Operations'),
              matching: find.byType(Row),
            )
            .first;
        final menu = find.descendant(
          of: row,
          matching: find.byIcon(Icons.more_vert),
        );
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await tester.tap(find.text(l10n.entryFieldMoveDown));
        await tester.pumpAndSettle();
        await saveForm(tester);
        final fields = (saves.single.content['fields'] as List).cast<Map>();
        expect(fields.map((field) => field['id']), [
          legacyId,
          otherId,
          opaqueId,
          collectionId,
          totpId,
          ordinaryId,
        ]);
        expect(fields[1], other);
        expect(fields[2], interleaved[2]);
        expect(fields[3], interleaved[3]);
      },
    );

    testWidgets(
      'new ordinary field Move up survives save with anchored neighbors',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith(interleaved),
          fieldAccess: interleavedAccess,
        );
        final saves = recordSaves(harness.canonical);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await enterEdit(tester);
        final add = find.text(l10n.entryAddFieldAction);
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.entryFieldTypeText));
        await tester.pumpAndSettle();
        final name = find
            .byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.hintText == l10n.entryFieldNameLabel,
            )
            .last;
        final value = find
            .byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.hintText == l10n.entryFieldValueLabel,
            )
            .last;
        await tester.enterText(name, 'New field B');
        await tester.enterText(value, 'New value B');
        final row = find
            .ancestor(
              of: find.widgetWithText(TextField, 'New value B'),
              matching: find.byType(Row),
            )
            .first;
        final menu = find.descendant(
          of: row,
          matching: find.byIcon(Icons.more_vert),
        );
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.entryFieldMoveUp));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.widgetWithText(TextField, 'New value B')).dy,
          lessThan(
            tester.getTopLeft(find.widgetWithText(TextField, 'Operations')).dy,
          ),
        );
        await saveForm(tester);
        final fields = (saves.single.content['fields'] as List).cast<Map>();
        expect(fields.map((field) => field['label']), [
          'Legacy',
          'New field B',
          'Opaque',
          'Github',
          'Authenticator',
          'Team',
        ]);
        expect(fields[0], interleaved[0]);
        expect(fields[2], interleaved[2]);
        expect(fields[3], interleaved[3]);
        expect(fields[4], interleaved[4]);
        expect(fields[5], interleaved[1]);
        expect(fields[1]['value'], 'New value B');
        expect(
          fields[1]['id'],
          isNot(isIn(interleaved.map((field) => field['id']))),
        );
        for (final access in interleavedAccess.entries) {
          expect(
            saves.single.policy?.fields[access.key]?.wireName,
            access.value,
          );
        }
      },
    );

    testWidgets(
      'method edit delete and add preserve neighboring positions and append the new ID',
      (tester) async {
        final harness = await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith(interleaved),
          fieldAccess: interleavedAccess,
        );
        final saves = recordSaves(harness.canonical);
        await enterEdit(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Operations'),
          'Updated operations',
        );
        await openMethod(tester, legacyId);
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('sign-in-method-account')),
            matching: find.byType(TextField),
          ),
          'edited@example.test',
        );
        await saveSheet(tester);
        await openMethod(tester, collectionId);
        await tester.ensureVisible(
          find.byKey(const ValueKey('sign-in-method-remove')),
        );
        await tester.tap(find.byKey(const ValueKey('sign-in-method-remove')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sign-in-method-add')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sign-in-method-provider')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apple').last);
        await tester.pumpAndSettle();
        await saveSheet(tester);
        await saveForm(tester);
        expect(saves, hasLength(1));
        final fields = (saves.single.content['fields'] as List).cast<Map>();
        expect(fields.take(4).map((field) => field['id']), [
          legacyId,
          ordinaryId,
          opaqueId,
          totpId,
        ]);
        expect(fields.first, {
          ...interleaved.first,
          'type': 'palladin.signin.v2',
          'value': {
            'provider': 'google',
            'account': 'edited@example.test',
            'entry': null,
          },
        });
        expect(fields[1], {...interleaved[1], 'value': 'Updated operations'});
        expect(fields[2], interleaved[2]);
        expect(fields[3], interleaved[4]);
        expect(
          fields.last['id'],
          isNot(isIn([legacyId, ordinaryId, opaqueId, collectionId, totpId])),
        );
        expect(fields.last['value'], {
          'provider': 'apple',
          'account': null,
          'entry': null,
        });
        expect(saves.single.policy?.fields[legacyId], AgentFieldAccess.never);
        expect(saves.single.policy?.fields[opaqueId], AgentFieldAccess.never);
        expect(saves.single.policy?.fields.containsKey(collectionId), isFalse);
      },
    );

    testWidgets('shows a recognized provider and account', (tester) async {
      await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith([
          binding({'provider': 'github', 'account': 'octo', 'entry': null}),
        ]),
      );
      expect(await rowText(tester), 'GitHub · octo');
    });

    testWidgets(
      'OAuth-only edit enables Save and last draft removal restores validation',
      (tester) async {
        await pumpTab(
          tester,
          entry: credential,
          payload: payloadWith([
            binding({
              'provider': 'google',
              'account': 'synthetic@example.test',
              'entry': null,
            }),
          ]),
        );
        await enterEdit(tester);
        expect(
          tester
              .widget<EntrySaveButton>(find.byType(EntrySaveButton))
              .onPressed,
          isNotNull,
        );
        final edit = find.byKey(
          const ValueKey(
            'sign-in-method-edit-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          ),
        );
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final remove = find.byKey(const ValueKey('sign-in-method-remove'));
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EntrySaveButton>(find.byType(EntrySaveButton))
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('shows a missing account explicitly', (tester) async {
      await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith([
          binding({'provider': 'apple', 'account': null, 'entry': null}),
        ]),
      );
      expect(await rowText(tester), 'Apple');
    });

    testWidgets('unrecognized bindings stay neutral', (tester) async {
      await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith([
          binding({'provider': 'twitter', 'account': 'x'}),
        ]),
      );
      expect(await rowText(tester), '');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('entry-sign-in-method')),
          matching: find.byIcon(Icons.content_copy),
        ),
        findsNothing,
      );
      expect(find.textContaining('twitter'), findsNothing);
    });

    testWidgets('ambiguous bindings stay neutral', (tester) async {
      await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith([
          binding({'provider': 'google', 'account': null, 'entry': null}),
          binding({
            'provider': 'github',
            'account': null,
            'entry': null,
          }, id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
        ]),
      );
      expect(await rowText(tester), 'Google · GitHub');
    });

    testWidgets('choosing a provider saves through the canonical update', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final (:cubit, :canonical) = await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith(const []),
      );
      expect(await rowText(tester), '');
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => CanonicalEntrySnapshot(
          entry: {'currentRevision': '1'},
          payload: payloadWith(const []),
          secret: {
            'entryType': EntryType.credential.toWire(),
            'memberLabel': 'Example',
            'agentLabel': 'Example',
            'agentVisibilityPolicy': {
              'discoverable': true,
              'fields': {'agentLabel': 'discovery', 'username': 'discovery'},
            },
          },
        ),
      );
      when(
        () => canonical.update(
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
      ).thenAnswer((_) async => credential);

      await tester.tap(find.byKey(const ValueKey('sign-in-method-add')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.entrySignInMethodRemove), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sign-in-method-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Microsoft').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('sign-in-method-account')),
          matching: find.byType(TextField),
        ),
        '  qa@example.test  ',
      );
      await tester.tap(find.text(l10n.entrySaveAction));
      await tester.pumpAndSettle();

      final content =
          verify(
                () => canonical.update(
                  snapshot: any(named: 'snapshot'),
                  expected: any(named: 'expected'),
                  label: any(named: 'label'),
                  description: any(named: 'description'),
                  icon: any(named: 'icon'),
                  type: any(named: 'type'),
                  content: captureAny(named: 'content'),
                  memberPrivateKey: any(named: 'memberPrivateKey'),
                  agentVisibilityPolicy: any(named: 'agentVisibilityPolicy'),
                  agentLabel: any(named: 'agentLabel'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final field = (content['fields'] as List).single as Map;
      expect(field['type'], 'palladin.signin.v2');
      expect(field['label'], l10n.entrySignInMethodLabel);
      expect(field['value'], {
        'provider': 'microsoft',
        'account': 'qa@example.test',
        'entry': null,
      });
      expect(cubit.isClosed, isFalse);
    });

    testWidgets('a failed save keeps the displayed details and edit base', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final (:cubit, :canonical) = await pumpTab(
        tester,
        entry: credential,
        payload: payloadWith(const []),
      );
      expect(find.text('qa@example.test'), findsOneWidget);
      when(
        () => canonical.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => CanonicalEntrySnapshot(
          entry: {'currentRevision': '1'},
          payload: payloadWith(const []),
          secret: {
            'entryType': EntryType.credential.toWire(),
            'memberLabel': 'Example',
            'agentLabel': 'Example',
            'agentVisibilityPolicy': {
              'discoverable': true,
              'fields': {'agentLabel': 'discovery', 'username': 'discovery'},
            },
          },
        ),
      );
      when(
        () => canonical.update(
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

      await tester.tap(find.byKey(const ValueKey('sign-in-method-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-in-method-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GitHub').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.entrySaveAction));
      await tester.pumpAndSettle();

      expect(cubit.state, isA<EditEntryError>());
      expect(find.text('qa@example.test'), findsOneWidget);
      expect(await rowText(tester), '');
      expect(cubit.hasCanonicalSnapshot, isTrue);
      ScaffoldMessenger.of(
        tester.element(find.byType(EntryDetailsTab)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await enterEdit(tester);
      final username = tester.widget<TextField>(
        find.widgetWithText(TextField, 'qa@example.test'),
      );
      expect(username.controller?.text, 'qa@example.test');
    });
  });
}
