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
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/core/widgets/skeleton_box.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/services/hibp_service.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/register_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/verify_email_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/register_page.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/verify_email_page.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/features/onboarding/data/datasources/onboarding_remote_datasource.dart';
import 'package:mobile_palladin/features/onboarding/data/services/default_vault_provisioner.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_copy_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_copy_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_recipient_authority.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_account_continuation.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_navigation.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_receiver_page.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

// This file talks only to its own loopback fixture; no backend or identity provider.
class _LoopbackBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _Config extends Mock implements EnvConfig {}

class _Repository extends Mock implements AuthRepository {}

class _Tokens extends Mock implements SecureTokenStorage {}

class _Login extends MockCubit<LoginState> implements LoginCubit {}

class _Hibp extends Mock implements HibpService {}

const _principal = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _organization = '11111111-1111-4111-8111-111111111111';
const _vault = '22222222-2222-4222-8222-222222222222';
const _entry = '33333333-3333-4333-8333-333333333333';
const _channel = MethodChannel('io.palladin.mobile/entry-sharing');

void main() {
  _LoopbackBinding();
  late SodiumSumo sodium;
  late HttpServer server;
  late AuthBloc auth;
  late VaultSessionStore keys;
  late EntryShareIngress ingress;
  late EntryShareAccountContinuation continuation;
  late EntryShareNavigation navigation;
  late GoRouter router;
  late Uint8List privateKey;
  late Map<String, dynamic> fixture;
  late String shareId;
  late RegisterCubit registration;
  late GlobalKey screenshot;
  final loginStreams = <StreamController<LoginState>>[];
  final routes = <String>[];
  final requests =
      <({String path, String method, String body, String? auth})>[];
  final vaultPosts = <String>[];
  final entryPosts = <String>[];
  Map<String, dynamic>? vaultJson;
  Map<String, Object?>? nativeReply;
  String? token;
  String principal = _principal;
  bool verified = true;
  bool? defaultProvisioned;
  int verificationChecks = 0;
  final registrations = <Map<String, dynamic>>[];
  int opens = 0, deliveries = 0, confirmations = 0, logins = 0;
  String scenario = 'happy';

  setUpAll(() async {
    final visualFont = Platform.environment['PALLADIN_SHARING_VISUAL_FONT'];
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          visualFont ??
              '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
    if (visualFont != null) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    sodium = await sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(
        Platform.environment['PALLADIN_LIBSODIUM_PATH'] ?? 'libsodium.so',
      ),
    );
    SodiumProvider.debugOverride = sodium;
    fixture =
        jsonDecode(
              File(
                'test/fixtures/crypto/entry-share-v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    shareId = fixture['scope']['shareId'] as String;
  });
  tearDownAll(() => SodiumProvider.debugOverride = null);

  String sessionToken() =>
      'e30.${base64UrlEncode(utf8.encode(jsonEncode({'sub': principal, 'org_id': _organization, 'authz_ver': 7, 'email_verified': verified})))}.synthetic';

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    final body = await utf8.decoder.bind(request).join();
    requests.add((
      path: path,
      method: request.method,
      body: body,
      auth: request.headers.value(HttpHeaders.authorizationHeader),
    ));
    Object? response;
    if (path == '/api/auth/register') {
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      final data = jsonDecode(body) as Map<String, dynamic>;
      registrations.add(data);
      principal = data['accountId'] as String;
      response = {
        'accessToken': sessionToken(),
        'refreshToken': 'fixture-refresh',
        'userId': principal,
        'isOnboarded': true,
        'emailVerified': false,
      };
    } else if (path.startsWith('/api/entry-shares/')) {
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
      expect(request.method, 'POST');
      if (path.endsWith('/sessions')) {
        opens++;
        response = {
          'sessionId': 'fixture-session',
          'sessionToken': 'fixture-token',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'shareExpiresAt': fixture['scope']['expiresAt'],
          'maximumReceipts': 1,
          'recipientMode': 'anyoneWithLink',
          'protection': 'none',
          'otpRetryAfterSeconds': 0,
        };
      } else if (path.endsWith('/delivery')) {
        deliveries++;
        if (deliveries > 1) {
          request.response.statusCode = 404;
        } else {
          response = {
            ...fixture['scope'] as Map<String, dynamic>,
            'nonce': fixture['nonce'],
            'ciphertext': fixture['ciphertext'],
          };
        }
      } else if (path.endsWith('/confirmation')) {
        confirmations++;
        request.response.statusCode = 204;
      } else {
        request.response.statusCode = 404;
      }
    } else {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $token',
      );
      switch ((request.method, path)) {
        case ('GET', '/api/vaults'):
          response = {
            'vaults': [if (vaultJson != null) vaultJson!],
            'total': vaultJson == null ? 0 : 1,
          };
        case ('GET', '/api/account'):
          response = {'userId': principal, 'memberKeyVersion': 1};
        case ('POST', '/api/vaults/creation-challenges'):
          response = {'vaultId': _vault};
        case ('POST', '/api/account/default-vault'):
          vaultPosts.add(body);
          final data = jsonDecode(body) as Map<String, dynamic>;
          vaultJson = {
            'id': _vault,
            'organizationId': _organization,
            'memberKeyGeneration': 1,
            'metadataRevision': '1',
            'memberVaultKey': data['creatorVaultKey'],
            'memberVaultMetadata': data['memberVaultMetadata'],
            'currentKeyEpoch': data['currentKeyEpoch'],
            'discoveryKey': data['discoveryKey'],
          };
          request.response.statusCode = 204;
        case ('GET', '/api/vaults/$_vault'):
          response = vaultJson;
        case ('POST', '/api/vaults/$_vault/entries/creation-challenges'):
          response = {
            'items': [
              {'entryId': _entry},
            ],
          };
        case ('POST', '/api/vaults/$_vault/entries'):
          entryPosts.add(body);
          request.response.statusCode =
              scenario == 'save-retry' && entryPosts.length == 1 ? 503 : 204;
        default:
          request.response.statusCode = 404;
      }
    }
    if (response != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
    }
    await request.response.close();
  }

  Future<void> drain(WidgetTester tester) async {
    // Let loopback I/O finish before fake-clock settling can fire HTTP timeouts.
    var settled = false;
    for (var i = 0; i < 500; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 8 &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(SkeletonBox).evaluate().isEmpty) {
        settled = true;
        break;
      }
    }
    expect(settled, true, reason: 'Loopback operation did not settle');
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await drain(tester);
  }

  Future<void> mount(WidgetTester tester, {bool polish = false}) async {
    await getIt.reset();
    screenshot = GlobalKey();
    token = null;
    principal = _principal;
    verified = !scenario.startsWith('register');
    defaultProvisioned = null;
    verificationChecks = 0;
    registrations.clear();
    vaultJson = null;
    nativeReply = null;
    opens = 0;
    deliveries = 0;
    confirmations = 0;
    logins = 0;
    routes.clear();
    requests.clear();
    vaultPosts.clear();
    entryPosts.clear();
    loginStreams.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = Size(polish ? 320 : 390, polish ? 568 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(handle);
    });
    final config = _Config();
    when(() => config.apiBaseUrl).thenReturn('http://127.0.0.1:${server.port}');
    when(() => config.certificatePins).thenReturn([]);
    final repository = _Repository();
    when(() => repository.isAuthenticated()).thenAnswer((_) async => false);
    when(() => repository.getUserId()).thenAnswer((_) async => principal);
    when(() => repository.getPermissions()).thenAnswer(
      (_) async => Permissions.vaultManage | Permissions.vaultCreate,
    );
    when(
      () => repository.getEmail(),
    ).thenAnswer((_) async => 'recipient@example.invalid');
    when(() => repository.isEmailVerified()).thenAnswer((_) async => verified);
    when(() => repository.refreshToken()).thenAnswer((_) async {
      verificationChecks++;
      if (scenario == 'register-check-error' && verificationChecks == 1) {
        throw StateError('Synthetic refresh failure');
      }
      verified = scenario != 'register-pending' || verificationChecks > 1;
      token = sessionToken();
    });
    when(
      () => repository.getAuthProvider(),
    ).thenAnswer((_) async => 'password');
    final tokens = _Tokens();
    when(() => tokens.accessToken).thenAnswer((_) async => token);
    when(
      () => tokens.defaultVaultProvisioned,
    ).thenAnswer((_) async => defaultProvisioned);
    when(() => tokens.setDefaultVaultProvisioned(any())).thenAnswer((
      call,
    ) async {
      defaultProvisioned = call.positionalArguments[0] as bool;
    });
    when(() => tokens.setAuthProvider(any())).thenAnswer((_) async {});
    when(
      () => tokens.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
        userId: any(named: 'userId'),
        isOnboarded: any(named: 'isOnboarded'),
      ),
    ).thenAnswer((call) async {
      token = call.namedArguments[#accessToken] as String;
    });
    keys = VaultSessionStore();
    privateKey = sodium.randombytes.buf(32);
    auth = AuthBloc(authRepository: repository, vaultSessionStore: keys);
    auth.add(const AuthCheckRequested());
    await tester.pump();
    final authority = EntryShareRecipientAuthority(tokens, keys);
    getIt.registerSingleton<EnvConfig>(config);
    getIt.registerSingleton<EntryShareRecipientAuthority>(authority);
    getIt.registerSingleton<EntryShareCryptoService>(
      EntryShareCryptoService(sodiumLoader: () async => sodium),
    );
    final accountHttp = Dio(BaseOptions(baseUrl: config.apiBaseUrl));
    accountHttp.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    );
    final passwordRemote = PasswordAuthRemoteDatasource(accountHttp);
    final provisioner = DefaultVaultProvisioner(
      remoteDatasource: OnboardingRemoteDatasource(accountHttp),
      vaultCryptoService: VaultCryptoService(sodiumLoader: () async => sodium),
      tokenStorage: tokens,
      accountRemoteDatasource: AccountRemoteDatasource(accountHttp),
    );
    final hibp = _Hibp();
    when(() => hibp.check(any())).thenAnswer((_) async => HibpResult.notFound);
    getIt.registerSingleton<HibpService>(hibp);
    getIt.registerFactory<RegisterCubit>(
      () => registration = RegisterCubit(
        datasource: passwordRemote,
        cryptoService: PasswordAuthCryptoService(
          sodiumLoader: () async => sodium,
        ),
        tokenStorage: tokens,
      ),
    );
    getIt.registerFactory<VerifyEmailCubit>(
      () => VerifyEmailCubit(
        datasource: passwordRemote,
        authRepository: repository,
        defaultVaultProvisioner: provisioner,
      ),
    );
    getIt.registerFactory<EntryShareCopyService>(
      () => EntryShareCopyService(
        remote: EntryShareCopyDatasource(config, tokens, keys),
        vaultCrypto: VaultCryptoService(sodiumLoader: () async => sodium),
        entryCrypto: EntryV2CryptoService(sodiumLoader: () async => sodium),
        autoFill: AutoFillMutationNotifier(),
      ),
    );
    getIt.registerFactory<LoginCubit>(() {
      final login = _Login();
      final events = StreamController<LoginState>.broadcast();
      loginStreams.add(events);
      whenListen(login, events.stream, initialState: const LoginInitial());
      when(
        () => login.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async {
        logins++;
        if (scenario == 'login-retry' && logins == 1) {
          events.add(const LoginFailure(InvalidCredentialsException()));
          return;
        }
        token = sessionToken();
        events.add(
          LoginSuccess(
            masterKey: Uint8List(32),
            privateKey: Uint8List.fromList(privateKey),
          ),
        );
      });
      return login;
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (_) async {
      final result = nativeReply;
      nativeReply = null;
      return result;
    });
    ingress = EntryShareIngress(
      links: EntryShareLinkService(
        EnvConfig.local(sharingWebOrigin: 'http://localhost'),
      ),
    );
    continuation = EntryShareAccountContinuation(
      auth: auth,
      ingress: ingress,
      ownerReader: authority.read,
    );
    router = createRouter(
      auth,
      sharingIngress: ingress,
      sharingAccount: continuation,
    );
    router.routeInformationProvider.addListener(
      () => routes.add(router.routeInformationProvider.value.uri.toString()),
    );
    navigation = EntryShareNavigation(ingress, router)..start();
    unawaited(ingress.start());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
      router.dispose();
      continuation.dispose();
      ingress.dispose();
      messenger.setMockMethodCallHandler(_channel, null);
      final closing = Future.wait([
        auth.close(),
        ...loginStreams.map((events) => events.close()),
      ]);
      await tester.pump();
      await closing;
      await tester.runAsync(() async {
        await server.close(force: true);
      });
      keys.clear();
      accountHttp.close(force: true);
      privateKey.fillRange(0, privateKey.length, 0);
      await getIt.reset();
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(polish ? 'pl' : 'en'),
          theme: ThemeData(
            brightness: polish ? Brightness.dark : Brightness.light,
            colorScheme: polish
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
            fontFamily: 'Roboto',
          ),
          builder: (context, child) => RepaintBoundary(
            key: screenshot,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(polish ? 1.5 : 1)),
              child: child!,
            ),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final capability = EntryShareSecrets(
      key: VaultProtocolBytes.hex(fixture['keyHex']),
      accessToken: Uint8List(32)..fillRange(0, 32, 7),
    );
    nativeReply = {
      'generation': 1,
      'url': 'http://localhost/share/$shareId${capability.toFragment()}',
      'receivedAtUnixMs': DateTime.now().millisecondsSinceEpoch,
      'ageMilliseconds': 0,
    };
    capability.dispose();
    messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(const MethodCall('pending', 1)),
      (_) {},
    );
    await drain(tester);
    expect(find.byType(EntryShareReceiverPage), findsOneWidget);
    expect(requests, isEmpty);
  }

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final field = find.descendant(
      of: find.widgetWithText(OnboardingTextField, label),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  for (final polish in [false, true]) {
    testWidgets(
      'sharing registration remains editable with keyboard: pl=$polish',
      (tester) async {
        scenario = 'register';
        await mount(tester, polish: polish);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EntryShareReceiverPage)),
        )!;
        await tap(tester, l10n.sharingOpen);
        await tap(tester, l10n.sharingReceive);
        await tap(tester, l10n.sharingRegister);
        expect(find.byType(RegisterPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['PALLADIN_SHARING_VISUAL_DIR'];
        Future<void> capture(String suffix) async {
          if (directory == null) return;
          await tester.runAsync(() async {
            final boundary =
                screenshot.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/sharing-register-${polish ? 'pl-dark-320-150' : 'en-light-390'}$suffix.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('');
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await enterField(tester, l10n.authEmailLabel, 'draft@example.invalid');
        await tester.pumpAndSettle();
        final email = find.descendant(
          of: find.widgetWithText(OnboardingTextField, l10n.authEmailLabel),
          matching: find.byType(EditableText),
        );
        final originalInput = tester.state(email);
        expect(tester.getRect(email).top, greaterThanOrEqualTo(0));
        expect(
          tester.getRect(email).bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height - 200),
        );
        expect(tester.takeException(), isNull);
        await capture('-keyboard');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tap(tester, l10n.sharingCancelReception);
        await tap(tester, l10n.sharingDiscardReception);
        expect(continuation.active, false);
        expect(tester.state(email), same(originalInput));
        expect(find.text('draft@example.invalid'), findsOneWidget);
        expect(registrations, isEmpty);
        expect((opens, deliveries, confirmations), (1, 1, 1));
        expect(router.routeInformationProvider.value.uri.path, '/register');
      },
    );
  }

  for (final variant in [
    'happy',
    'login-retry',
    'save-retry',
    'register',
    'register-pending',
    'register-check-error',
  ]) {
    testWidgets(
      'guest receipt survives production account routing and first-vault save: $variant',
      (tester) async {
        scenario = variant;
        await mount(tester);
        await tap(tester, 'Open sharing');
        await tap(tester, 'Receive entry');
        expect(deliveries, 1);
        expect(confirmations, 1);
        final lifetime = tester
            .widget<EntryShareReceiverPage>(find.byType(EntryShareReceiverPage))
            .cubit
            .lifetime;
        final registering = variant.startsWith('register');
        if (registering) {
          await tap(tester, 'Create an account to save a copy');
          expect(find.byType(RegisterPage), findsOneWidget);
          for (final (label, value) in [
            ('Email', 'recipient@example.invalid'),
            ('Master Password', 'Fixture-only! violet lantern 842#'),
            ('Confirm Password', 'Fixture-only! violet lantern 842#'),
          ]) {
            await enterField(tester, label, value);
          }
          await drain(tester);
          await tap(tester, 'Sign Up');
          expect(registration.state.step, RegisterStep.recoveryKeyBackup);
          final recoveryWords = List<String>.of(registration.state.mnemonic);
          await tap(tester, "I've Saved My Recovery Key");
          for (final input
              in tester
                  .widgetList<OnboardingTextField>(
                    find.byType(OnboardingTextField),
                  )
                  .toList()) {
            final label = input.label!;
            final index = int.parse(label.split('#').last) - 1;
            await enterField(tester, label, recoveryWords[index]);
          }
          await tap(tester, 'Verify & Complete Setup');
          expect(find.byType(VerifyEmailPage), findsOneWidget);
          expect(continuation.active, true);
          expect((opens, deliveries, confirmations), (1, 1, 1));
          expect(vaultPosts, isEmpty);
          expect(registrations, hasLength(1));
          expect(
            jsonEncode(registrations.single),
            isNot(contains(recoveryWords.join(' '))),
          );
          privateKey.fillRange(0, privateKey.length, 0);
          privateKey = Uint8List.fromList(
            (auth.state as AuthAuthenticated).privateKey!,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(continuation.active, true);
          expect((opens, deliveries, confirmations), (1, 1, 1));
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await drain(tester);
          await tap(tester, "I've verified my email");
          if (variant != 'register') {
            expect(find.byType(VerifyEmailPage), findsOneWidget);
            expect(continuation.active, true);
            expect(vaultPosts, isEmpty);
            expect((opens, deliveries, confirmations), (1, 1, 1));
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            await tap(tester, "I've verified my email");
          }
          expect(defaultProvisioned, true);
          expect(verificationChecks, variant == 'register' ? 1 : 2);
        } else {
          await tap(tester, 'Sign in to save a copy');
          expect(find.byType(LoginPage), findsOneWidget);
          await tap(tester, 'Continue with Email');
          for (final (label, value) in [
            ('Email', 'recipient@example.invalid'),
            ('Master Password', 'synthetic-input-only'),
          ]) {
            final field = find.descendant(
              of: find.widgetWithText(OnboardingTextField, label),
              matching: find.byType(TextField),
            );
            await tester.ensureVisible(field);
            await tester.enterText(field, value);
          }
          await tap(tester, 'Sign In');
          if (variant == 'login-retry') {
            expect(find.byType(LoginPage), findsOneWidget);
            expect(continuation.active, true);
            expect((opens, deliveries, confirmations), (1, 1, 1));
            await tap(tester, 'Sign In');
          }
          expect(logins, variant == 'login-retry' ? 2 : 1);
        }
        expect(router.routeInformationProvider.value.uri.toString(), '/share');
        expect(
          tester
              .widget<EntryShareReceiverPage>(
                find.byType(EntryShareReceiverPage),
              )
              .cubit
              .lifetime,
          same(lifetime),
        );
        await tap(tester, 'Save a copy');
        expect(vaultPosts, hasLength(registering ? 1 : 0));
        expect(entryPosts, isEmpty);
        if (!registering) await tap(tester, 'Create my personal vault');
        expect(vaultPosts, hasLength(1));
        await drain(tester);
        expect(
          tester
              .widget<PrimaryButton>(
                find.widgetWithText(PrimaryButton, 'Save a copy'),
              )
              .onPressed,
          isNull,
        );
        final dropdown = find.descendant(
          of: find.byKey(const ValueKey('sharing-copy-vault')),
          matching: find.byType(DropdownButton<String>),
        );
        expect(
          find.byKey(const ValueKey('sharing-copy-vault')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          dropdown,
          -180,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.ensureVisible(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personal').last);
        await tester.pumpAndSettle();
        final username = find.descendant(
          of: find.byKey(const ValueKey('sharing-copy-credential.username')),
          matching: find.byType(TextField),
        );
        await tester.scrollUntilVisible(
          username,
          180,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.ensureVisible(username);
        await tester.enterText(username, 'recipient username');
        await tap(tester, 'Save a copy');
        expect(entryPosts, hasLength(1));
        if (variant == 'save-retry') {
          expect(find.text('Retry same request'), findsOneWidget);
          expect((opens, deliveries, confirmations), (1, 1, 1));
          await tap(tester, 'Retry same request');
          expect(entryPosts, hasLength(2));
          expect(entryPosts.last, entryPosts.first);
        }
        expect(
          find.text(
            'Copy saved in your vault. It will not sync with the original.',
          ),
          findsOneWidget,
        );
        expect((opens, deliveries, confirmations), (1, 1, 1));
        expect(
          routes,
          everyElement(
            registering
                ? anyOf('/register', '/verify-email', '/share')
                : anyOf('/login', '/share'),
          ),
        );
        expect(
          requests.where(
            (request) =>
                request.path ==
                '/api/vaults/$_vault/entries/creation-challenges',
          ),
          hasLength(1),
        );
        for (final request in requests) {
          expect(request.body, isNot(contains('fixture-only')));
          expect(request.body, isNot(contains('recipient username')));
          expect(
            request.body,
            isNot(contains('Fixture-only! violet lantern 842#')),
          );
          expect(request.body, isNot(contains(base64Encode(privateKey))));
        }
        expect(
          requests
              .where((request) => request.path.startsWith('/api/entry-shares/'))
              .every((request) => request.auth == null),
          true,
        );
        await tester.runAsync(() async {
          final opened = await VaultCryptoService(
            sodiumLoader: () async => sodium,
          ).openVaultProjection(json: vaultJson!, memberPrivateKey: privateKey);
          try {
            final entry = jsonDecode(entryPosts.first) as Map<String, dynamic>;
            final secret =
                await EntryV2CryptoService(
                  sodiumLoader: () async => sodium,
                ).openMemberSecret(
                  entryKey: entry['entryKey'],
                  memberSecret: entry['memberSecret'],
                  vaultKey: opened.vaultKey,
                );
            expect((secret['content'] as Map)['password'], 'fixture-only');
            expect(
              (secret['content'] as Map)['username'],
              'recipient username',
            );
            expect(secret['discoverable'], false);
          } finally {
            opened.vaultKey.fillRange(0, opened.vaultKey.length, 0);
            opened.vaultDiscoveryKey?.fillRange(
              0,
              opened.vaultDiscoveryKey!.length,
              0,
            );
          }
        });
      },
    );
  }
}
