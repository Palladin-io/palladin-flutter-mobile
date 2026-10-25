import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/autofill/presentation/widgets/autofill_setup_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  const channel = MethodChannel('io.palladin.mobile/autofill');
  var status = 'disabled';
  var opens = 0;
  setUp(() {
    status = 'disabled';
    opens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getProviderStatus') return status;
          if (call.method == 'openProviderSettings') {
            opens++;
            return null;
          }
          throw MissingPluginException();
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> pump(WidgetTester tester, {bool hideWhenEnabled = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AutoFillSetupCard(hideWhenEnabled: hideWhenEnabled),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first display warns until OS confirms selection; opens only on tap',
    (tester) async {
      await pump(tester, hideWhenEnabled: true);
      expect(find.text('Set up AutoFill'), findsOneWidget);
      expect(opens, 0);
      await tester.tap(find.text('Open AutoFill settings'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(find.text('Set up AutoFill'), findsOneWidget);
      status = 'enabled';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Set up AutoFill'), findsNothing);
    },
  );

  testWidgets('settings keeps confirmed enabled status visible', (
    tester,
  ) async {
    status = 'enabled';
    await pump(tester);
    expect(find.text('Palladin is enabled for AutoFill'), findsOneWidget);
  });

  testWidgets(
    'legacy iOS provides manual steps without claiming settings opened',
    (tester) async {
      status = 'manual';
      await pump(tester);
      expect(
        find.textContaining('Passwords → Password Options'),
        findsOneWidget,
      );
      expect(find.text('Open AutoFill settings'), findsNothing);
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(opens, 0);
    },
  );

  testWidgets('enabled legacy iOS still offers only manual settings guidance', (
    tester,
  ) async {
    status = 'enabledManual';
    await pump(tester);
    expect(find.text('Palladin is enabled for AutoFill'), findsOneWidget);
    expect(find.text('Open AutoFill settings'), findsNothing);
  });

  testWidgets('missing native bridge reports failure instead of hiding setup', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    await pump(tester, hideWhenEnabled: true);
    expect(find.text('Could not check AutoFill. Try again.'), findsOneWidget);
  });

  testWidgets('failed status check never claims selection', (tester) async {
    status = 'invalid';
    await pump(tester);
    expect(find.text('Could not check AutoFill. Try again.'), findsOneWidget);
    expect(find.text('Palladin is enabled for AutoFill'), findsNothing);
  });
}
