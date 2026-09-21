import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_palladin/core/storage/user_preferences.dart';
import 'package:mobile_palladin/features/shell/presentation/cubit/library_view_cubit.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/shell_tab_page.dart';
import 'package:mobile_palladin/core/widgets/app_fab.dart';
import 'package:mobile_palladin/core/widgets/list_screen_header.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/entry_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/global_entries_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/vault_list_page.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/add_entry_page.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/choose_entry_vault_sheet.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_library_switch.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Vaults extends MockCubit<VaultListState> implements VaultListCubit {}

class _Entries extends Mock implements EntryRepository {}

class _Index implements MemberIndexReader {
  @override
  Future<void> waitForCurrent(String vaultId) async {}
  @override
  List<MemberIndexEntry> entries(String vaultId) => List.generate(
    80,
    (i) => MemberIndexEntry(
      entryId: '$i',
      entryType: i % 4,
      memberLabel: 'Entry ${i.toString().padLeft(2, '0')}',
      searchFields: const [],
      revision: '1',
      state: MemberEntryState.active,
    ),
  );
}

class _Loader implements MemberEntryListLoader {
  @override
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) async => [];
  @override
  void lock() {}
}

void main() {
  testWidgets(
    'library routes preserve separate search and scroll, then clear on lock',
    (tester) async {
      await getIt.reset();
      FlutterSecureStorage.setMockInitialValues({});
      final libraryPreference = LibraryViewCubit(
        const UserPreferences(FlutterSecureStorage()),
      );
      addTearDown(libraryPreference.close);
      addTearDown(getIt.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Optional local visual artifact: ordinary CI runs neither read a system
      // font nor write a screenshot. Both inputs are explicit test-run options.
      const fontPath = String.fromEnvironment('ENTRIES_PREVIEW_FONT');
      if (fontPath.isNotEmpty) {
        await tester.runAsync(() async {
          final bytes = await File(fontPath).readAsBytes();
          final loader = FontLoader('PreviewFont')
            ..addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        });
      }
      final auth = _Auth();
      final vaults = _Vaults();
      final authEvents = StreamController<AuthState>.broadcast();
      addTearDown(authEvents.close);
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
      final items = List.generate(
        20,
        (i) => VaultEntity(
          id: 'vault-$i',
          name: 'Vault ${i.toString().padLeft(2, '0')}',
          grantMode: GrantMode.granular,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          entryCount: 80,
          activeGrantCount: 0,
          memberCount: 1,
        ),
      );
      whenListen(
        vaults,
        const Stream<VaultListState>.empty(),
        initialState: VaultListLoaded(items),
      );
      when(
        () => vaults.loadIfNeeded(any<Uint8List?>()),
      ).thenAnswer((_) async {});
      when(vaults.lock).thenReturn(null);
      getIt.registerSingleton<VaultListCubit>(vaults);
      getIt.registerFactory<CreateEntryCubit>(
        () => CreateEntryCubit(repository: _Entries()),
      );
      getIt.registerFactory<GlobalEntriesCubit>(
        () => GlobalEntriesCubit(
          index: _Index(),
          loader: _Loader(),
          indexUpdates: const Stream.empty(),
        ),
      );
      final router = GoRouter(
        initialLocation: '/vaults',
        routes: [
          for (final entries in [false, true])
            GoRoute(
              path: entries ? '/entries' : '/vaults',
              pageBuilder: (_, _) => ShellTabPage(
                pageKey: VaultListPage.pageKey,
                direction: ShellTabDirection.none,
                disableAnimations: true,
                child: VaultListPage(entries: entries),
              ),
            ),
        ],
      );
      addTearDown(router.dispose);
      final boundary = GlobalKey();
      AppFab? activeFab;
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: fontPath.isEmpty ? null : 'PreviewFont',
              ),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) => BlocProvider.value(
              value: libraryPreference,
              child: AppShellScope(
                openSettingsDrawer: () {},
                setBottomNavHidden: (_) {},
                setFab: (fab, _) => activeFab = fab is AppFab ? fab : null,
                clearFab: (_) {},
                child: RepaintBoundary(key: boundary, child: child!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalPageState = tester.state(find.byType(VaultListPage));
      expect(activeFab, isA<AppFab>());
      expect(activeFab!.tooltip, 'New Vault');
      expect(
        tester.getTopLeft(find.byTooltip('Entries')).dx,
        lessThan(tester.getTopLeft(find.byTooltip('Vaults')).dx),
      );
      expect(
        find.descendant(
          of: find.byType(ListScreenHeader),
          matching: find.byType(VaultLibrarySwitch),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(VaultLibrarySwitch),
        ),
        findsNothing,
      );
      final switchY = tester.getTopLeft(find.byType(VaultLibrarySwitch)).dy;
      await tester.enterText(find.byType(TextField), 'Vault 0');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -280));
      await tester.pumpAndSettle();
      final vaultOffset = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(vaultOffset, greaterThan(0));
      expect(tester.getTopLeft(find.byType(VaultLibrarySwitch)).dy, switchY);
      await tester.tap(find.byTooltip('Entries'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/entries');
      expect(tester.state(find.byType(VaultListPage)), same(originalPageState));
      expect(find.byIcon(Icons.tune), findsNothing);
      final totalLabel = AppLocalizations.of(
        tester.element(find.byType(VaultListPage)),
      )!.vaultEntryCount(1600);
      expect(find.text(totalLabel), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Entry 0');
      await tester.pumpAndSettle();
      expect(find.text(totalLabel), findsOneWidget);

      const screenshotPath = String.fromEnvironment('ENTRIES_PREVIEW_PNG');
      if (screenshotPath.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(screenshotPath).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
      await tester.pumpAndSettle();
      final scroller = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final savedOffset = scroller.position.pixels;
      expect(savedOffset, greaterThan(0));

      // The global action must ask for a Vault before mounting any form.
      activeFab!.onPressed();
      await tester.pumpAndSettle();
      expect(find.byType(ChooseEntryVaultSheet), findsOneWidget);
      expect(find.byType(AddEntryPage), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byType(ChooseEntryVaultSheet),
          matching: find.byType(TextField),
        ),
        'Vault 07',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vault 07').last);
      await tester.pumpAndSettle();
      final form = tester.widget<AddEntryPage>(find.byType(AddEntryPage));
      expect(form.vaultId, 'vault-7');
      expect(form.vaultName, 'Vault 07');
      expect(find.text('Vault 07'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AddEntryPage), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/entries');
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(savedOffset, 1),
      );

      router.go('/vaults');
      await tester.pumpAndSettle();
      final vaultPosition = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(vaultPosition.pixels, closeTo(vaultOffset, 1));
      vaultPosition.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Vault 0',
      );
      router.go('/entries');
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        closeTo(savedOffset, 1),
      );
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Entry 0',
      );
      router.go('/vaults');
      await tester.pumpAndSettle();
      authEvents.add(const AuthInitial());
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      router.go('/entries');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Entry 00'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
