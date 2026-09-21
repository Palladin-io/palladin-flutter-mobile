import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
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
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/core/widgets/skeleton_box.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
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
  final loginStreams = <StreamController<LoginState>>[];
  final routes = <String>[];
  final requests =
      <({String path, String method, String body, String? auth})>[];
  final vaultPosts = <String>[];
  final entryPosts = <String>[];
  Map<String, dynamic>? vaultJson;
  Map<String, Object?>? nativeReply;
  String? token;
  int opens = 0, deliveries = 0, confirmations = 0, logins = 0;
  String scenario = 'happy';

  setUpAll(() async {
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
    if (path.startsWith('/api/entry-shares/')) {
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
          response = {'userId': _principal, 'memberKeyVersion': 1};
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

  Future<void> mount(WidgetTester tester) async {
    await getIt.reset();
    token = null;
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
    tester.view.physicalSize = const Size(390, 844);
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
    when(() => repository.getUserId()).thenAnswer((_) async => _principal);
    when(() => repository.getPermissions()).thenAnswer(
      (_) async => Permissions.vaultManage | Permissions.vaultCreate,
    );
    when(
      () => repository.getEmail(),
    ).thenAnswer((_) async => 'recipient@example.invalid');
    when(() => repository.isEmailVerified()).thenAnswer((_) async => true);
    when(
      () => repository.getAuthProvider(),
    ).thenAnswer((_) async => 'password');
    final tokens = _Tokens();
    when(() => tokens.accessToken).thenAnswer((_) async => token);
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
        token =
            'e30.${base64UrlEncode(utf8.encode(jsonEncode({'sub': _principal, 'org_id': _organization, 'authz_ver': 7})))}.synthetic';
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
      privateKey.fillRange(0, privateKey.length, 0);
      await getIt.reset();
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
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

  for (final variant in ['happy', 'login-retry', 'save-retry']) {
    testWidgets(
      'guest receipt survives production login routing and first-vault save: $variant',
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
        expect(vaultPosts, isEmpty);
        expect(entryPosts, isEmpty);
        await tap(tester, 'Create my personal vault');
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
        expect(routes, everyElement(anyOf('/login', '/share')));
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
