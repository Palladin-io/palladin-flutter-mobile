import 'package:flutter/material.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/theme/app_theme.dart';
import 'package:mobile_palladin/core/theme/theme_cubit.dart';
import 'package:mobile_palladin/core/l10n/locale_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/shell/presentation/cubit/library_view_cubit.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'settings_adapters.dart';
import 'preview_binding.dart';
import 'phone_frame.dart';
import 'bootstrap.dart';
import 'activity_adapters.dart';
import 'vault_adapters.dart';

Future<void> main() async {
  PreviewBinding();
  await registerPreviewBootstrap();
  await registerVaultPreview();
  registerActivityPreview();
  await registerSettingsPreview();
  final auth = getIt<AuthBloc>().state;
  if (auth is AuthAuthenticated) {
    await getIt<VaultListCubit>().loadVaults(auth.privateKey);
  }
  runApp(const MobilePreviewApp());
}

class MobilePreviewApp extends StatefulWidget {
  const MobilePreviewApp({super.key});
  @override
  State<MobilePreviewApp> createState() => _MobilePreviewAppState();
}

class _MobilePreviewAppState extends State<MobilePreviewApp> {
  final prefs = PreviewPreferences();
  late final router = createRouter(getIt<AuthBloc>());
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ConsentCubit(
          MemoryConsentRemoteDataSource(),
          AnalyticsService.instance,
        )..bind('demo-user', 'en'),
      ),
      BlocProvider<AuthBloc>.value(value: getIt<AuthBloc>()),
      BlocProvider(create: (_) => LibraryViewCubit(prefs)),
      BlocProvider(create: (_) => ThemeCubit(prefs, initial: prefs.theme)),
      BlocProvider(create: (_) => LocaleCubit(prefs)),
    ],
    child: Builder(
      builder: (context) => MaterialApp.router(
        title: 'Palladin · Mobile design',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        darkTheme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
        themeMode: context.watch<ThemeCubit>().state,
        locale: context.watch<LocaleCubit>().state,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) => PreviewPhoneFrame(child: child!),
      ),
    ),
  );
}
