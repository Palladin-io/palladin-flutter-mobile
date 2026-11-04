import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/storage/account_secret_store.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/secret_key/data/services/emergency_kit_pdf_service.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/emergency_kit_settings_cubit.dart';
import 'package:mobile_palladin/features/secret_key/presentation/emergency_kit_export.dart';
import 'package:mobile_palladin/features/secret_key/presentation/pages/emergency_kit_settings_page.dart';
import 'package:mobile_palladin/features/secret_key/presentation/widgets/emergency_kit_step.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';

class _Store extends Mock implements AccountSecretStore {}

class _Kdf extends Mock implements IdentityKdfService {}

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _accountId = '00112233-4455-6677-8899-aabbccddeeff';
final _secret = Uint8List.fromList(List.generate(32, (i) => i + 1));
const _display =
    'PSK2-041061-050R3G-G28A1C-60T3GF-208H44-RM2MB1-E60S38-DHR78Y-3WG06J';

Future<ByteData> _font(String asset) async =>
    ByteData.sublistView(await File(asset).readAsBytes());

const _labels = EmergencyKitLabels(
  title: 'Palladin Emergency Kit',
  intro: 'Zaloguj się na nowym urządzeniu: ąęłńóśźż',
  account: 'E-mail konta',
  secretKey: 'Secret Key',
  secretKeyQr: 'Kod QR',
  masterPassword: 'Hasło główne',
  signInAddress: 'Adres logowania',
  generated: 'Utworzono',
  footer: 'Stopka',
);

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AppShellScope(
    openSettingsDrawer: () {},
    setBottomNavHidden: (_) {},
    setFab: (_, _) {},
    clearFab: (_) {},
    child: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  group('EmergencyKitPdfService', () {
    test(
      'builds a PDF with Polish labels and shares a deleted temp copy',
      () async {
        final temp = await Directory.systemTemp.createTemp('kit-test');
        String? sharedPath;
        var existedDuringShare = false;
        final service = EmergencyKitPdfService(
          assetLoader: _font,
          temporaryDirectory: () async => temp,
          shareFile: (file) async {
            sharedPath = file.path;
            existedDuringShare = File(file.path).existsSync();
          },
        );
        final bytes = await service.build(
          email: 'user@example.com',
          accountId: _accountId,
          accountSecret: _secret,
          signInAddress: 'https://stage.palladin.io',
          generatedDate: '4 listopada 2026',
          labels: _labels,
        );
        expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');

        await service.share(bytes);
        expect(existedDuringShare, isTrue);
        expect(sharedPath, endsWith(EmergencyKitPdfService.fileName));
        expect(File(sharedPath!).existsSync(), isFalse);
        await temp.delete(recursive: true);
      },
    );

    test('sign-in address prefers the web origin, else strips api.', () {
      expect(
        emergencyKitSignInAddress(
          EnvConfig.staging(
            apiBaseUrl: 'https://api.stage.palladin.io',
            sharingWebOrigin: '',
          ),
        ),
        'https://stage.palladin.io',
      );
      expect(
        emergencyKitSignInAddress(
          EnvConfig.staging(
            apiBaseUrl: 'https://api.stage.palladin.io',
            sharingWebOrigin: 'https://app.example',
          ),
        ),
        'https://app.example',
      );
    });
  });

  group('EmergencyKitStep', () {
    testWidgets('Continue needs a saved kit and the confirmation', (
      tester,
    ) async {
      final shared = <XFile>[];
      final temp = Directory.systemTemp.createTempSync('kit-step');
      final service = EmergencyKitPdfService(
        assetLoader: _font,
        temporaryDirectory: () async => temp,
        shareFile: (file) async => shared.add(file),
      );
      var continued = false;
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          EmergencyKitStep(
            email: 'user@example.com',
            accountId: _accountId,
            accountSecret: _secret,
            onContinue: () => continued = true,
            pdfService: service,
            config: EnvConfig.staging(
              apiBaseUrl: 'https://api.stage.palladin.io',
              sharingWebOrigin: '',
            ),
          ),
        ),
      );
      expect(find.text(_display), findsOneWidget);
      expect(find.textContaining('recovery phrase'), findsWidgets);

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(continued, isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.text('Save Emergency Kit (PDF)'));
        for (var i = 0; i < 50 && shared.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));

      await tester.tap(find.byKey(const ValueKey('emergencyKitSavedConfirm')));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      expect(continued, isTrue);
      temp.deleteSync(recursive: true);
    });
  });

  group('EmergencyKitSettingsCubit', () {
    late _Store store;
    late _Kdf kdf;
    final masterKey = Uint8List.fromList(List.filled(32, 7));
    const metadata = IdentityKdfMetadata(
      securityVersion: 2,
      minimumSecurityVersion: 2,
      profileId: IdentityKdfProfileV2.id,
      kdfSalt: 'oKGio6SlpqeoqaqrrK2urw',
      credentialRevision: 1,
      privateKeyWrapRevision: 1,
    );

    setUp(() {
      store = _Store();
      kdf = _Kdf();
      when(
        () => kdf.assertSupported(any()),
      ).thenReturn(IdentityKdfVersion.accountSecretV2);
    });

    EmergencyKitSettingsCubit build() => EmergencyKitSettingsCubit(
      accountId: _accountId,
      store: store,
      loadAccount: () async => const AccountResponse(
        userId: _accountId,
        email: 'user@example.com',
        kdf: metadata,
      ),
      kdfService: kdf,
    );

    setUpAll(() => registerFallbackValue(metadata));

    void deriveReturns(Uint8List key) =>
        when(
          () => kdf.deriveV2(
            password: any(named: 'password'),
            accountId: any(named: 'accountId'),
            kdfSalt: any(named: 'kdfSalt'),
            accountSecret: any(named: 'accountSecret'),
          ),
        ).thenAnswer(
          (_) async => IdentityKdfOutputs(
            authCredential: Uint8List(32),
            masterKey: Uint8List.fromList(key),
          ),
        );

    blocTest<EmergencyKitSettingsCubit, EmergencyKitSettingsState>(
      'reports a device without a Secret Key',
      setUp: () =>
          when(() => store.read(_accountId)).thenAnswer((_) async => null),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<EmergencyKitSettingsLoading>(),
        isA<EmergencyKitSettingsMissing>(),
      ],
    );

    test(
      'masks the Secret Key and exports only after the password matches',
      () async {
        when(
          () => store.read(_accountId),
        ).thenAnswer((_) async => Uint8List.fromList(_secret));
        final cubit = build();
        await cubit.load();
        final ready = cubit.state as EmergencyKitSettingsReady;
        expect(ready.maskedSecretKey, 'PSK2-••••••-••••••-…-••G06J');

        final exported = <List<int>>[];
        deriveReturns(Uint8List(32));
        await cubit.exportKit(
          password: 'wrong',
          sessionMasterKey: masterKey,
          export: (_, secret) async => exported.add(List.of(secret)),
        );
        expect(
          (cubit.state as EmergencyKitSettingsReady).wrongPassword,
          isTrue,
        );
        expect(exported, isEmpty);

        deriveReturns(masterKey);
        await cubit.exportKit(
          password: 'right',
          sessionMasterKey: masterKey,
          export: (email, secret) async {
            expect(email, 'user@example.com');
            exported.add(List.of(secret));
          },
        );
        expect((cubit.state as EmergencyKitSettingsReady).exported, isTrue);
        expect(exported.single, _secret);
        await cubit.close();
      },
    );
  });

  group('EmergencyKitSettingsPage', () {
    testWidgets('shows the locked state without an unlocked session', (
      tester,
    ) async {
      final auth = _AuthBloc();
      whenListen(
        auth,
        const Stream<AuthState>.empty(),
        initialState: const AuthAuthenticated(
          userId: _accountId,
          isOnboarded: true,
        ),
      );
      await tester.pumpWidget(
        _app(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: const EmergencyKitSettingsPage(),
          ),
          locale: const Locale('pl'),
        ),
      );
      expect(
        find.text('Odblokuj Palladin, aby zapisać Emergency Kit.'),
        findsOneWidget,
      );
    });

    testWidgets('renders the masked key and password confirmation', (
      tester,
    ) async {
      final auth = _AuthBloc();
      whenListen(
        auth,
        const Stream<AuthState>.empty(),
        initialState: AuthAuthenticated(
          userId: _accountId,
          isOnboarded: true,
          isVaultLocked: false,
          masterKey: Uint8List(32),
          privateKey: Uint8List(32),
        ),
      );
      final store = _Store();
      when(
        () => store.read(_accountId),
      ).thenAnswer((_) async => Uint8List.fromList(_secret));
      await tester.pumpWidget(
        _app(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: EmergencyKitSettingsPage(
              cubitBuilder: (accountId) => EmergencyKitSettingsCubit(
                accountId: accountId,
                store: store,
                loadAccount: () async => const AccountResponse(
                  userId: _accountId,
                  email: 'user@example.com',
                ),
                kdfService: _Kdf(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PSK2-••••••-••••••-…-••G06J'), findsOneWidget);
      expect(find.text(_display), findsNothing);
      expect(find.text('Create Emergency Kit'), findsOneWidget);
    });
  });
}
