import 'package:flutter/material.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/widgets/app_fab.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/settings/presentation/bloc/permissions_cubit.dart';
import 'package:mobile_palladin/features/settings/presentation/pages/permission_role_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import '../../../../design/mobile/settings_adapters.dart';

void main() {
  testWidgets(
    'role opens read-only; cancel discards draft and save returns to details',
    (tester) async {
      final repository = MemorySettingsRepository();
      getIt.registerFactory<PermissionsCubit>(
        () => PermissionsCubit(repository: repository),
      );
      addTearDown(getIt.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Scaffold(
              bottomNavigationBar: const Text('shell navigation'),
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) =>
                      const PermissionRolePage(roleId: 'role-engineer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('shell navigation'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      await tester.tap(find.byType(AppFab));
      await tester.pumpAndSettle();
      expect(find.text('shell navigation'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Discarded role');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        (await repository.listOrganizationRoles()).items.any(
          (r) => r.name == 'Discarded role',
        ),
        isFalse,
      );
      await tester.tap(find.byType(AppFab));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Audit role');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('shell navigation'), findsOneWidget);
      expect(
        (await repository.listOrganizationRoles()).items
            .singleWhere((r) => r.id == 'role-engineer')
            .name,
        'Audit role',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
