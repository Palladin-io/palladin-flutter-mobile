import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_detail_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import '../../design/mobile/bootstrap.dart';
import '../../design/mobile/vault_adapters.dart';
import '../../design/mobile/activity_adapters.dart';
import '../../design/mobile/settings_adapters.dart';

void main() {
  testWidgets('Entry detail stays inside the shell and returns to its list', (
    tester,
  ) async {
    await registerPreviewBootstrap();
    await registerVaultPreview();
    registerActivityPreview();
    await registerSettingsPreview();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: getIt<AuthBloc>(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppShellScope(
            openSettingsDrawer: () {},
            setBottomNavHidden: (_) {},
            setFab: (_, _) {},
            clearFab: (_) {},
            child: Scaffold(
              bottomNavigationBar: const Text('persistent navbar'),
              body: Navigator(
                key: navigator,
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (context) => TextButton(
                    onPressed: () => EntryDetailPage.push(
                      context,
                      entry: vaultPreview.records['entry-github']!,
                    ),
                    child: const Text('Open entry'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailPage), findsOneWidget);
    expect(find.text('persistent navbar'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Open entry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await getIt.reset();
  });
}
