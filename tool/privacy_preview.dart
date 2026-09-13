// Debug-only host for the real privacy widgets and Cubit using a localhost synthetic API.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_palladin/core/analytics/analytics_service.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/privacy/data/consent_activation_store.dart';
import 'package:mobile_palladin/features/privacy/data/consent_remote_datasource.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_onboarding_page.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_settings_page.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  if (!kDebugMode) throw UnsupportedError('Debug-only preview');
  WidgetsFlutterBinding.ensureInitialized();
  HttpClient.enableTimelineLogging =
      true; // Passive VM HTTP profiling, no request interception.
  runApp(const Preview());
}

class Preview extends StatefulWidget {
  const Preview({super.key});
  @override
  State<Preview> createState() => _PreviewState();
}

class _PreviewState extends State<Preview> {
  final analytics = AnalyticsService();
  late final dio = Dio(
    BaseOptions(
      baseUrl: 'http://127.0.0.1:45619',
      headers: {'X-Preview-Account': 'fixture-native'},
    ),
  );
  late final cubit = ConsentCubit(
    ConsentRemoteDataSource(dio),
    ConsentActivationStore(
      cacheDirectory: () async =>
          Directory('${Directory.systemTemp.path}/cvt609-preview'),
    ),
    analytics,
  );
  final navigator = GlobalKey<NavigatorState>();
  String locale = 'en';
  bool dialog = true;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    analytics.configure(
      projectKey: '',
      host: 'https://eu.i.posthog.com',
      released: false,
    );
    _reset();
    developer.registerExtension('ext.palladin.preview', (_, parameters) async {
      if (parameters.containsKey('screen') ||
          parameters.containsKey('locale')) {
        navigator.currentState?.popUntil((route) => route.isFirst);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (parameters['locale'] case final value?) {
          locale = value == 'pl' ? 'pl' : 'en';
        }
        if (parameters['reset'] == 'true') await _reset();
        setState(() {
          dialog = parameters['screen'] != 'settings';
          revision++;
        });
      }
      if (parameters['action'] case final action?) {
        final l10n = await AppLocalizations.delegate.load(Locale(locale));
        var invoked = false;
        void visit(Element element) {
          final widget = element.widget;
          if (!invoked &&
              widget is Semantics &&
              widget.properties.label ==
                  (action == 'analytics'
                      ? l10n.privacyAnalytics
                      : l10n.privacyMarketing) &&
              (action == 'analytics' || action == 'marketing')) {
            widget.properties.onTap?.call();
            invoked = true;
          }
          if (!invoked &&
              (action == 'save' ||
                  action == 'essential' ||
                  action == 'activate')) {
            if (widget is ButtonStyleButton && widget.child is Text) {
              final label = (widget.child! as Text).data;
              if (label ==
                  (action == 'save'
                      ? l10n.privacySaveChoice
                      : action == 'essential'
                      ? l10n.privacyEssentialOnly
                      : l10n.privacyActivateHere)) {
                widget.onPressed?.call();
                invoked = true;
              }
            }
          }
          element.visitChildren(visit);
        }

        WidgetsBinding.instance.rootElement?.visitChildren(visit);
        if (!invoked) throw StateError('Preview control not found');
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'locale': locale,
          'dialog': dialog,
          'release': false,
          'projectKeyEmpty': true,
          'locallyActive': cubit.state.locallyActive,
          'transportInitialized': analytics.isInitialized,
          'consents': cubit.state.consents
              .map((c) => {'purpose': c.purpose, 'status': c.status})
              .toList(),
        }),
      );
    });
  }

  Future<void> _reset() async {
    await cubit.bind(null, locale);
    await dio.post<void>('/reset');
    await cubit.bind('fixture-native', locale);
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: cubit,
    child: MaterialApp(
      navigatorKey: navigator,
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: AppColors.brandRed,
        scaffoldBackgroundColor: AppColors.lightBackground,
      ),
      builder: (context, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            child: SafeArea(
              bottom: false,
              child: const Text('TEST FIXTURE · native Flutter · capture off'),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child!,
            ),
          ),
        ],
      ),
      home: AppShellScope(
        openSettingsDrawer: () {},
        setBottomNavHidden: (_) {},
        setFab: (_, _) {},
        clearFab: (_) {},
        child: dialog
            ? PrivacyOnboardingPage(
                key: ValueKey('dialog-$revision'),
                onCompleted: () => setState(() {
                  dialog = false;
                }),
              )
            : PrivacySettingsPage(key: ValueKey('settings-$revision')),
      ),
    ),
  );
}
