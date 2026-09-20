import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_reception.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_reception_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_receiver_page.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_field_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Remote extends Mock implements EntryShareRecipientDatasource {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const EntryShareRecipientOwner _guest = (
  principalId: null,
  organizationId: null,
  authorizationGeneration: null,
  keyGeneration: 0,
);
final _fixture =
    jsonDecode(
          File('test/fixtures/crypto/entry-share-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
final _shareId = _fixture['scope']['shareId'] as String;
final _now = DateTime.utc(2026, 9, 21);

void main() {
  late SodiumSumo sodium;
  late _Remote remote;
  late _Auth auth;
  late StreamController<AuthState> authEvents;
  late EntryShareReceptionCubit cubit;
  late EntryShareSecrets secrets;
  late EntryShareRecipientOwner? owner;
  late EntryShareRecipientSession session;
  late GlobalKey<NavigatorState> navigator;
  late GlobalKey screenshotKey;
  String? clipboard;
  bool clipboardFails = false;

  setUpAll(() async {
    registerFallbackValue(CancelToken());
    registerFallbackValue(
      const EntryShareRecipientSession(
        sessionId: '',
        sessionToken: '',
        expiresAt: '',
        recipientMode: '',
        protection: '',
      ),
    );
    final path = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = path != null || Platform.isLinux
        ? await sodium_ffi.SodiumSumoInit.init(
            () => DynamicLibrary.open(path ?? 'libsodium.so'),
          )
        : await SodiumSumoInit.init();
    final font = Platform.environment['PALLADIN_SHARING_VISUAL_FONT'];
    if (font != null) {
      await (FontLoader(
        'SharingVisualInter',
      )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  setUp(() {
    remote = _Remote();
    auth = _Auth();
    authEvents = StreamController<AuthState>();
    whenListen(
      auth,
      authEvents.stream,
      initialState: const AuthUnauthenticated(),
    );
    owner = _guest;
    navigator = GlobalKey<NavigatorState>();
    screenshotKey = GlobalKey();
    clipboard = null;
    clipboardFails = false;
    secrets = EntryShareSecrets(
      key: VaultProtocolBytes.hex(_fixture['keyHex']),
      accessToken: Uint8List(32)..fillRange(0, 32, 7),
    );
    session = EntryShareRecipientSession(
      sessionId: 'synthetic',
      sessionToken: 'synthetic-token',
      expiresAt: _now.add(const Duration(minutes: 10)).toIso8601String(),
      recipientMode: 'anyoneWithLink',
      protection: 'none',
    );
    when(
      () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async => session);
    when(
      () => remote.requestOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        language: any(named: 'language'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.verifyOtp(
        any(),
        any(),
        generation: any(named: 'generation'),
        code: any(named: 'code'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.verifySecret(
        any(),
        any(),
        secret: any(named: 'secret'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async {
      final scope = _fixture['scope'];
      return EntryShareDelivery(
        authority: EntryShareScope(
          shareId: scope['shareId'],
          organizationId: scope['organizationId'],
          vaultId: scope['vaultId'],
          entryId: scope['entryId'],
          sourceRevision: scope['sourceRevision'],
          expiresAt: scope['expiresAt'],
        ),
        packet: EntryShareCiphertext(
          nonce: _fixture['nonce'],
          ciphertext: _fixture['ciphertext'],
        ),
      );
    });
    when(
      () => remote.confirmDisplay(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) async {});
    cubit = EntryShareReceptionCubit(
      remote: remote,
      crypto: EntryShareCryptoService(sodiumLoader: () async => sodium),
      shareId: _shareId,
      secrets: secrets,
      owner: _guest,
      ownerReader: () async => owner,
      now: () => _now,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (clipboardFails) {
              owner = null;
              throw PlatformException(code: 'synthetic failure');
            }
            clipboard = (call.arguments as Map)['text'];
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    await authEvents.close();
    await auth.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(
    WidgetTester tester, {
    String language = 'en',
    bool dark = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          navigatorKey: navigator,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: AppColors.brandRed,
                    error: AppColors.brandRed,
                    surface: AppColors.darkSurface,
                  )
                : const ColorScheme.light(
                    primary: AppColors.brandRed,
                    error: AppColors.brandRed,
                    surface: AppColors.lightSurface,
                    onSurface: AppColors.darkBackground,
                    onPrimary: AppColors.onBrandRed,
                  ),
            fontFamily:
                Platform.environment.containsKey('PALLADIN_SHARING_VISUAL_FONT')
                ? 'SharingVisualInter'
                : null,
          ),
          builder: (context, child) => RepaintBoundary(
            key: screenshotKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: const Scaffold(body: Text('Host')),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => EntryShareReceiverPage(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<void> receive(WidgetTester tester) async {
    await tap(tester, 'Open sharing');
    await tap(tester, 'Receive entry');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 46));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final dir = Platform.environment['PALLADIN_SHARING_VISUAL_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'guest opens explicitly, displays masked snapshot and ACKs only after frame',
    (tester) async {
      when(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {
        expect(find.text(_fixture['snapshot']['title']), findsOneWidget);
      });
      await mount(tester);
      verifyZeroInteractions(remote);
      expect(
        find.textContaining('without creating an account'),
        findsOneWidget,
      );
      await receive(tester);
      expect(cubit.state.phase, EntryShareReceptionPhase.received);
      expect(cubit.state.confirmation, EntryShareConfirmation.confirmed);
      final password = (_fixture['snapshot']['fields'] as List).firstWhere(
        (f) => f['type'] == 'concealed',
      )['value'];
      expect(find.text(password), findsNothing);
      expect(find.byType(EntryShareFieldCard), findsWidgets);
      await capture(tester, 'receiver-en-light-390');
      await finish(tester);
      expect(secrets.key, everyElement(0));
    },
  );

  testWidgets('OTP and PIN inputs validate and clear before sending', (
    tester,
  ) async {
    session = EntryShareRecipientSession(
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
      recipientMode: 'namedRecipient',
      protection: 'pin',
    );
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tap(tester, 'Send email code');
    final pin = find.byWidgetPredicate(
      (w) => w is OnboardingTextField && w.label == 'PIN',
    );
    await tester.ensureVisible(pin);
    await tester.enterText(pin, '123');
    await tap(tester, 'Verify protection');
    verifyNever(
      () => remote.verifySecret(
        any(),
        any(),
        secret: any(named: 'secret'),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
    await tester.enterText(pin, '001234');
    await tap(tester, 'Verify protection');
    final otp = find.byWidgetPredicate(
      (w) => w is OnboardingTextField && w.label == 'Email code',
    );
    await tester.ensureVisible(otp);
    await tester.enterText(otp, '012345');
    await tap(tester, 'Verify email code');
    expect(cubit.state.gatesReady, true);
    expect(find.byType(OnboardingTextField), findsNothing);
    verify(
      () => remote.verifySecret(
        _shareId,
        session,
        secret: '001234',
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
    verify(
      () => remote.verifyOtp(
        _shareId,
        session,
        generation: 1,
        code: '012345',
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(1);
    await finish(tester);
  });

  testWidgets('failed ACK retries ACK only while retaining displayed copy', (
    tester,
  ) async {
    var attempts = 0;
    when(
      () => remote.confirmDisplay(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      if (++attempts == 1) throw const EntryShareRecipientRequestException();
    });
    await mount(tester);
    await receive(tester);
    expect(cubit.state.confirmation, EntryShareConfirmation.failed);
    await tap(tester, 'Retry confirmation');
    expect(cubit.state.confirmation, EntryShareConfirmation.confirmed);
    verify(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).called(1);
    await finish(tester);
  });

  testWidgets('copy is explicit and clipboard error rechecks changed owner', (
    tester,
  ) async {
    await mount(tester);
    await receive(tester);
    expect(clipboard, isNull);
    clipboardFails = true;
    await tester.ensureVisible(find.byTooltip('Copy value').first);
    await tester.tap(find.byTooltip('Copy value').first);
    await tester.pumpAndSettle();
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    expect(find.byType(EntryShareFieldCard), findsNothing);
    await finish(tester);
  });

  testWidgets('successful copy preserves exact text and clears clipboard', (
    tester,
  ) async {
    await mount(tester);
    await receive(tester);
    await tester.ensureVisible(find.byTooltip('Copy value').first);
    await tester.tap(find.byTooltip('Copy value').first);
    await tester.pumpAndSettle();
    expect(clipboard, _fixture['snapshot']['fields'][0]['value']);
    await tester.pump(const Duration(seconds: 46));
    expect(clipboard, '');
    await finish(tester);
  });

  testWidgets('end requires confirmation and cancel keeps capability', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tap(tester, 'End sharing');
    expect(find.textContaining('End this link for everyone'), findsOneWidget);
    await tap(tester, 'Cancel');
    verifyNever(
      () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
    );
    await tap(tester, 'End sharing');
    await tap(tester, 'End link');
    expect(cubit.state.phase, EntryShareReceptionPhase.ended);
    expect(find.textContaining('Sharing ended.'), findsOneWidget);
    expect(secrets.key, everyElement(0));
    await finish(tester);
  });

  testWidgets('auth replacement closes open end sheet and drops reception', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tap(tester, 'End sharing');
    expect(find.textContaining('End this link for everyone'), findsOneWidget);
    authEvents.add(
      const AuthAuthenticated(userId: 'new-user', isOnboarded: true),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('End this link for everyone'), findsNothing);
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    verifyNever(
      () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
    );
    await finish(tester);
  });

  testWidgets('background clears plaintext and resume does not restore it', (
    tester,
  ) async {
    await mount(tester);
    await receive(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.byType(EntryShareFieldCard), findsNothing);
    expect(secrets.key, everyElement(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    await finish(tester);
  });

  testWidgets('background rejects a late delivery failure without an ACK', (
    tester,
  ) async {
    final delivery = Completer<EntryShareDelivery>();
    when(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).thenAnswer((_) => delivery.future);
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tester.tap(find.text('Receive entry'));
    await tester.pump();
    expect(cubit.state.busy, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    delivery.completeError(const EntryShareRecipientRequestException());
    await tester.pumpAndSettle();
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    expect(find.byType(EntryShareFieldCard), findsNothing);
    verifyNever(
      () => remote.confirmDisplay(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
    expect(secrets.key, everyElement(0));
    await finish(tester);
  });

  testWidgets('background immediately clears unsubmitted PIN and email code', (
    tester,
  ) async {
    session = EntryShareRecipientSession(
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
      recipientMode: 'namedRecipient',
      protection: 'pin',
    );
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tap(tester, 'Send email code');
    final fields = tester
        .widgetList<OnboardingTextField>(find.byType(OnboardingTextField))
        .toList();
    expect(fields, hasLength(2));
    for (final field in fields) {
      field.controller.text = '012345';
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    for (final field in fields) {
      expect(field.controller.text, isEmpty);
    }
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingTextField), findsNothing);
    await finish(tester);
  });

  testWidgets('unsupported future protection is readable but cannot receive', (
    tester,
  ) async {
    session = EntryShareRecipientSession(
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
      recipientMode: 'anyoneWithLink',
      protection: 'future-proof',
    );
    await mount(tester);
    await tap(tester, 'Open sharing');
    expect(cubit.state.phase, EntryShareReceptionPhase.verification);
    expect(find.text('Receive entry'), findsNothing);
    expect(find.text('End sharing'), findsNothing);
    verifyNever(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    );
    await finish(tester);
  });

  testWidgets('covering the page invalidates it even after returning', (
    tester,
  ) async {
    await mount(tester);
    await receive(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    expect(find.byType(EntryShareFieldCard), findsNothing);
    await finish(tester);
  });

  testWidgets('email app roundtrip resumes the same pending OTP session', (
    tester,
  ) async {
    session = EntryShareRecipientSession(
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
      recipientMode: 'namedRecipient',
      protection: 'none',
    );
    await mount(tester);
    await tap(tester, 'Open sharing');
    await tap(tester, 'Send email code');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingTextField), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingTextField), findsOneWidget);
    await tester.enterText(find.byType(OnboardingTextField), '012345');
    await tap(tester, 'Verify email code');
    await tap(tester, 'Receive entry');
    expect(cubit.state.phase, EntryShareReceptionPhase.received);
    verify(
      () => remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).called(1);
    verify(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).called(1);
    await finish(tester);
  });

  testWidgets(
    'authority timer clears old owner without waiting for user action',
    (tester) async {
      await mount(tester);
      await receive(tester);
      owner = null;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      await finish(tester);
    },
  );

  testWidgets('PL dark 320px at 150 percent fits verification and keyboard', (
    tester,
  ) async {
    session = EntryShareRecipientSession(
      sessionId: session.sessionId,
      sessionToken: session.sessionToken,
      expiresAt: session.expiresAt,
      recipientMode: 'namedRecipient',
      protection: 'pin',
    );
    await mount(tester, language: 'pl', dark: true, width: 320, scale: 1.5);
    await tap(tester, 'Otwórz udostępnienie');
    await tap(tester, 'Wyślij kod e-mail');
    expect(tester.takeException(), isNull);
    await capture(tester, 'receiver-pl-dark-320-150');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final pin = find.byWidgetPredicate(
      (w) => w is OnboardingTextField && w.label == 'PIN',
    );
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(pin, 160, scrollable: scrollable);
    await tester.enterText(pin, '001234');
    await tester.scrollUntilVisible(
      find.text('Potwierdź'),
      160,
      scrollable: scrollable,
    );
    await tap(tester, 'Potwierdź');
    expect(cubit.state.secretVerified, true);
    await finish(tester);
  });

  testWidgets(
    'PL narrow large-text end confirmation keeps both actions usable',
    (tester) async {
      await mount(tester, language: 'pl', dark: true, width: 320, scale: 1.5);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetViewPadding);
      await tap(tester, 'Otwórz udostępnienie');
      await tap(tester, 'Zakończ udostępnianie');
      expect(tester.takeException(), isNull);
      await capture(tester, 'receiver-end-pl-dark-320-150');
      await tap(tester, 'Anuluj');
      expect(cubit.state.phase, EntryShareReceptionPhase.verification);
      verifyNever(
        () => remote.end(any(), any(), cancelToken: any(named: 'cancelToken')),
      );
      await finish(tester);
    },
  );
}
