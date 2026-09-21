import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/vault_exceptions.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/choose_entry_vault_sheet.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class AuthMock extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class VaultsMock extends MockCubit<VaultListState> implements VaultListCubit {}

VaultEntity vault(String id, String name) => VaultEntity(
  id: id,
  name: name,
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 0,
  activeGrantCount: 0,
  memberCount: 1,
);

void main() {
  late AuthMock auth;
  late VaultsMock vaults;
  late StreamController<AuthState> authEvents;
  VaultEntity? selected;
  var created = false;

  setUp(() {
    auth = AuthMock();
    vaults = VaultsMock();
    authEvents = StreamController.broadcast();
    selected = null;
    created = false;
    whenListen(
      auth,
      authEvents.stream,
      initialState: AuthAuthenticated(
        userId: 'user',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
      ),
    );
  });
  tearDown(() async {
    await authEvents.close();
    await auth.close();
    await vaults.close();
  });

  Future<void> open(WidgetTester tester, VaultListState state) async {
    whenListen(
      vaults,
      const Stream<VaultListState>.empty(),
      initialState: state,
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: auth),
          BlocProvider<VaultListCubit>.value(value: vaults),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<VaultEntity>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ChooseEntryVaultSheet(
                      onCreateFirstVault: () => created = true,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'requires explicit selection and returns the searched Vault identity',
    (tester) async {
      await open(
        tester,
        VaultListLoaded([vault('a', 'Personal'), vault('b', 'Work')]),
      );
      expect(selected, isNull);
      await tester.enterText(find.byType(TextField), 'work');
      await tester.pumpAndSettle();
      expect(find.text('Personal'), findsNothing);
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'b');
      expect(find.byType(ChooseEntryVaultSheet), findsNothing);
    },
  );

  testWidgets('lock dismisses the picker without selecting a Vault', (
    tester,
  ) async {
    await open(tester, VaultListLoaded([vault('a', 'Personal')]));
    authEvents.add(const AuthInitial());
    await tester.pumpAndSettle();
    expect(find.byType(ChooseEntryVaultSheet), findsNothing);
    expect(selected, isNull);
  });

  testWidgets(
    'no Vault offers creation; a failed list is not a loading spinner',
    (tester) async {
      await open(tester, const VaultListLoaded([]));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ChooseEntryVaultSheet)),
      )!;
      await tester.tap(find.text(l10n.vaultNewVault));
      expect(created, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('list error is visible', (tester) async {
    await open(tester, const VaultListError(VaultErrorKind.unknown));
    expect(find.byType(ChooseEntryVaultSheet), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
