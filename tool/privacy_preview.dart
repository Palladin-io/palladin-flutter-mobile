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
import 'package:mobile_palladin/core/widgets/sheet_action_buttons.dart';
import 'package:mobile_palladin/core/widgets/sheet_surface.dart';
import 'package:mobile_palladin/features/privacy/data/consent_remote_datasource.dart';
import 'package:mobile_palladin/features/privacy/presentation/consent_cubit.dart';
import 'package:mobile_palladin/features/privacy/presentation/privacy_consent_sheet.dart';
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
  late final cubit = ConsentCubit(ConsentRemoteDataSource(dio), analytics);
  final navigator = GlobalKey<NavigatorState>();
  String locale = 'en';
  bool dialog = true;
  bool transitioning = false;
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
        transitioning = true;
        revision++;
        navigator.currentState?.popUntil((route) => route.isFirst);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (parameters['locale'] case final value?) {
          locale = value == 'pl' ? 'pl' : 'en';
        }
        if (parameters['reset'] == 'true') await _reset();
        setState(() {
          dialog = parameters['screen'] != 'settings';
        });
        transitioning = false;
      }
      if (parameters['action'] == 'details') {
        await _showNoticeDetails(
          parameters['purpose'] == 'email_marketing' ? 1 : 0,
          bottom: parameters['bottom'] == 'true',
        );
      } else if (parameters['action'] == 'back') {
        await navigator.currentState?.maybePop();
      } else if (parameters['action'] case final action?) {
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
              (action == 'save' || action == 'accept' || action == 'open')) {
            if (widget is ButtonStyleButton && widget.child is Text) {
              final label = (widget.child! as Text).data;
              if (label ==
                  (action == 'save'
                      ? l10n.privacySaveChoice
                      : action == 'accept'
                      ? l10n.privacyAcceptAll
                      : l10n.privacyManageChoices)) {
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
          'sheetOpen': navigator.currentState?.canPop() ?? false,
          'release': false,
          'projectKeyEmpty': true,
          'analyticsAuthorized': cubit.state.analyticsAuthorized,
          'transportInitialized': analytics.isInitialized,
          'layout': _sheetLayout(),
          'consents': cubit.state.consents
              .map((c) => {'purpose': c.purpose, 'status': c.status})
              .toList(),
        }),
      );
    });
  }

  // Read-only geometry from the real render tree for native layout evidence.
  Map<String, Object> _sheetLayout() {
    final result = <String, Object>{};
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    result['viewport'] = {
      'width': view.physicalSize.width / view.devicePixelRatio,
      'height': view.physicalSize.height / view.devicePixelRatio,
    };
    void visit(Element element, bool inSheet) {
      final widget = element.widget;
      inSheet = inSheet || widget is SheetSurface;
      final name = widget is SheetSurface
          ? 'sheet'
          : inSheet && widget is SheetActionButtons
          ? 'footer'
          : inSheet && widget is SingleChildScrollView
          ? 'scroll'
          : null;
      final box = element.findRenderObject();
      if (name != null && box is RenderBox) {
        final position = box.localToGlobal(Offset.zero);
        result[name] = {
          'x': position.dx,
          'y': position.dy,
          'width': box.size.width,
          'height': box.size.height,
        };
      }
      element.visitChildren((child) => visit(child, inSheet));
    }

    WidgetsBinding.instance.rootElement?.visitChildren((e) => visit(e, false));
    return result;
  }

  Future<void> _showNoticeDetails(int index, {required bool bottom}) async {
    final tiles = <Element>[];
    void collect(Element element) {
      if (element.widget is ExpansionTile) tiles.add(element);
      element.visitChildren(collect);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(collect);
    final tile = tiles[index];
    ExpansibleController? controller;
    void findController(Element element) {
      controller ??= ExpansibleController.maybeOf(element);
      element.visitChildren(findController);
    }

    tile.visitChildren(findController);
    controller!.expand();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    Element? text;
    void findText(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data?.startsWith('TEST FIXTURE') == true) {
        text = element;
      }
      element.visitChildren(findText);
    }

    tile.visitChildren(findText);
    await Scrollable.ensureVisible(text!, alignment: bottom ? 1 : 0);
  }

  VoidCallback _completeStartup(int expectedRevision) => () {
    // A fixture-mode switch must not be overwritten by the old sheet's dismissal.
    if (transitioning || expectedRevision != revision || !mounted) return;
    setState(() => dialog = false);
  };

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
            ? _StartupSheetPreview(
                key: ValueKey('dialog-$revision'),
                onCompleted: _completeStartup(revision),
              )
            : _StartupSheetPreview(
                key: ValueKey('settings-$revision'),
                source: 'mobile_settings',
                onCompleted: () {},
              ),
      ),
    ),
  );
}

/// The preview opens the same sheet the runtime presents above the ready app.
class _StartupSheetPreview extends StatefulWidget {
  const _StartupSheetPreview({
    super.key,
    required this.onCompleted,
    this.source = 'mobile_onboarding',
  });
  final String source;
  final VoidCallback onCompleted;
  @override
  State<_StartupSheetPreview> createState() => _StartupSheetPreviewState();
}

class _StartupSheetPreviewState extends State<_StartupSheetPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPrivacyConsentSheet(context, source: widget.source);
      if (mounted) widget.onCompleted();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Application'));
}
