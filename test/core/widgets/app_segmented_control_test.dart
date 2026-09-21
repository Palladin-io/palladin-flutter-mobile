import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_palladin/core/storage/user_preferences.dart';
import 'package:mobile_palladin/features/shell/presentation/cubit/library_view_cubit.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_palladin/core/theme/app_spacing.dart';
import 'package:mobile_palladin/core/widgets/app_segmented_control.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/vault_library_switch.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'shared segment preserves the 44px track and emits selected value',
    (tester) async {
      var value = 'vaults';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: AppSegmentedControl<String>(
                    value: value,
                    options: const [
                      AppSegment(value: 'vaults', label: 'Vaults'),
                      AppSegment(value: 'entries', label: 'Entries', badge: 3),
                    ],
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AppSegmentedControl<String>)).height,
        AppSpacing.controlHeight,
      );
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Entries'));
      await tester.pump();
      expect(value, 'entries');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library segments navigate to separate Vaults and Entries routes',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final preferences = LibraryViewCubit(
        const UserPreferences(FlutterSecureStorage()),
      );
      addTearDown(preferences.close);
      String? hint;
      final router = GoRouter(
        initialLocation: '/vaults',
        routes: [
          GoRoute(
            path: '/vaults',
            builder: (_, _) =>
                const Scaffold(body: VaultLibrarySwitch(entries: false)),
          ),
          GoRoute(
            path: '/entries',
            builder: (_, _) =>
                const Scaffold(body: VaultLibrarySwitch(entries: true)),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => BlocProvider.value(
            value: preferences,
            child: AppShellScope(
              openSettingsDrawer: () {},
              setBottomNavHidden: (_) {},
              setFab: (_, _) {},
              clearFab: (_) {},
              showFabToast: (message) => hint = message,
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Entries'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/entries');
      expect(preferences.route, '/entries');
      expect(hint, contains('all your entries across vaults'));
      await tester.tap(find.byTooltip('Vaults'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/vaults');
      expect(preferences.route, '/vaults');
      expect(hint, contains('your entries grouped into vaults'));
      expect(tester.takeException(), isNull);
    },
  );
}
