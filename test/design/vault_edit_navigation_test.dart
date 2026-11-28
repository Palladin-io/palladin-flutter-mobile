import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/widgets/app_fab.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_settings_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_list_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/domain/repositories/vault_repository.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_detail_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/vault_detail_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import '../../design/mobile/bootstrap.dart';
import '../../design/mobile/vault_adapters.dart';
import '../../design/mobile/activity_adapters.dart';
import '../../design/mobile/settings_adapters.dart';

class _RetrySettings implements VaultSettingsService {
  _RetrySettings(this.delegate);
  final VaultSettingsService delegate;
  int calls = 0;
  @override
  Future<VaultEntity> update({
    required VaultEntity expected,
    required String name,
    required String description,
    required String icon,
    required String color,
    required Uint8List memberPrivateKey,
    String? localIconPath,
  }) async {
    if (++calls == 1) {
      throw const VaultSettingsException(VaultSettingsErrorKind.network);
    }
    return delegate.update(
      expected: expected,
      name: name,
      description: description,
      icon: icon,
      color: color,
      memberPrivateKey: memberPrivateKey,
      localIconPath: localIconPath,
    );
  }
}

void main() {
  testWidgets(
    'Vault edit retains its draft after network failure and retries above shell',
    (tester) async {
      await registerPreviewBootstrap();
      await registerVaultPreview();
      registerActivityPreview();
      await registerSettingsPreview();
      addTearDown(getIt.reset);
      final settings = _RetrySettings(getIt<VaultSettingsService>());
      await getIt.unregister<VaultDetailCubit>();
      getIt.registerFactory(
        () => VaultDetailCubit(
          repository: getIt<VaultRepository>(),
          listService: getIt<VaultListCryptoService>(),
          settingsService: settings,
        ),
      );
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
                bottomNavigationBar: const Text('shell navigation'),
                body: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute(
                    builder: (_) =>
                        const VaultDetailPage(vaultId: 'vault-personal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppFab));
      await tester.pumpAndSettle();
      expect(find.text('shell navigation'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Personal renamed');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(settings.calls, 1);
      expect(find.text('Personal renamed'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(settings.calls, 2);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('shell navigation'), findsOneWidget);
      expect(vaultPreview.vaults['vault-personal']!.name, 'Personal renamed');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
