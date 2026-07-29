import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';
import 'package:mobile_palladin/core/utils/secure_clipboard.dart';
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
  const masked = '••••••••••••';

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
    registerFallbackValue(Uint8List(0));
  });

  Future<EditEntryCubit> pumpTab(
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
        secret: {'schemaVersion': 1},
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
    return cubit;
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
    expect(find.text(masked), findsOneWidget);
    expect(find.text(secret), findsNothing);
    verify(
      () => canonical.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
  });

  testWidgets('read-only view masks the secret, the eye toggle reveals it, and '
      'copy writes the plaintext to the clipboard', (tester) async {
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});

    // Secret starts masked — the plaintext is never rendered up-front.
    expect(find.text(masked), findsOneWidget);
    expect(find.text(secret), findsNothing);

    // Tapping the eye toggle reveals the plaintext.
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text(secret), findsOneWidget);
    expect(find.text(masked), findsNothing);

    // Tapping copy writes the plaintext to the clipboard.
    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pump();
    expect(clipboardCalls, hasLength(1));
    expect((clipboardCalls.single.arguments as Map)['text'], secret);

    // Drain SecureClipboard's auto-clear timer so it isn't left pending.
    await tester.pump(
      SecureClipboard.defaultClearAfter + const Duration(seconds: 1),
    );
  });

  testWidgets('tapping Edit switches the read-only view into the edit form', (
    tester,
  ) async {
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Read-only mode: the danger zone is available here too, but there are no
    // editable fields yet.
    expect(find.text(l10n.entryDangerZone), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Edit sits below the encrypted fields — scroll it into view before tapping.
    final editButton = find.text(l10n.entryEditAction);
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Edit mode: the editable form is now shown.
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('background transition drops decrypted and revealed state', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await pumpTab(tester, entry: _keyEntry(), payload: {'value': secret});
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text(secret), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(find.text(secret), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(masked), findsOneWidget);
  });
}
