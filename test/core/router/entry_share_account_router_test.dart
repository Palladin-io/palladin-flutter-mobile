import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/storage/secure_token_storage.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/login_cubit.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_recipient_authority.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_reception_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_account_continuation.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_account_frame.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_receiver_frame.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Login extends MockCubit<LoginState> implements LoginCubit {}

class _Repository extends Mock implements AuthRepository {}

class _Tokens extends Mock implements SecureTokenStorage {}

class _Remote extends Mock implements EntryShareRecipientDatasource {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthBloc auth;
  late _Repository repository;
  late _Login login;
  late _Tokens tokens;
  late _Remote remote;
  late VaultSessionStore keys;
  late EntryShareIngress ingress;
  late EntryShareRecipientAuthority authority;
  late EntryShareAccountContinuation continuation;
  late EntryShareReceptionCubit reception;
  late EntryShareSecrets secrets;
  late StreamController<LoginState> loginEvents;
  late GoRouter router;
  late DateTime now;
  late Future<EntryShareRecipientOwner?> Function(String?) ownerReader;
  late GlobalKey screenshot;
  String? token;

  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });

  Future<void> mount(WidgetTester tester, {bool polish = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = Size(polish ? 320 : 390, polish ? 568 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await getIt.reset();
    token = null;
    now = DateTime.utc(2026, 9, 21);
    screenshot = GlobalKey();
    repository = _Repository();
    when(() => repository.isAuthenticated()).thenAnswer((_) async => false);
    when(() => repository.getUserId()).thenAnswer((_) async => 'recipient');
    when(() => repository.getPermissions()).thenAnswer((_) async => 0);
    when(
      () => repository.getEmail(),
    ).thenAnswer((_) async => 'test@example.invalid');
    when(() => repository.isEmailVerified()).thenAnswer((_) async => true);
    when(
      () => repository.getAuthProvider(),
    ).thenAnswer((_) async => 'password');
    keys = VaultSessionStore();
    auth = AuthBloc(authRepository: repository, vaultSessionStore: keys);
    auth.add(const AuthCheckRequested());
    await tester.pump();
    expect(auth.state, isA<AuthUnauthenticated>());
    login = _Login();
    loginEvents = StreamController<LoginState>.broadcast();
    whenListen(login, loginEvents.stream, initialState: const LoginInitial());
    getIt.registerFactory<LoginCubit>(() => login);
    tokens = _Tokens();
    when(() => tokens.accessToken).thenAnswer((_) async => token);
    authority = EntryShareRecipientAuthority(tokens, keys);
    ownerReader = authority.read;
    ingress = EntryShareIngress(
      links: EntryShareLinkService(
        EnvConfig.local(sharingWebOrigin: 'http://localhost'),
      ),
    );
    continuation = EntryShareAccountContinuation(
      auth: auth,
      ingress: ingress,
      ownerReader: (id) => ownerReader(id),
    );
    remote = _Remote();
    secrets = EntryShareSecrets(
      key: Uint8List(32)..fillRange(0, 32, 1),
      accessToken: Uint8List(32)..fillRange(0, 32, 2),
    );
    final guest = (await authority.read(null))!;
    reception = EntryShareReceptionCubit(
      remote: remote,
      crypto: EntryShareCryptoService(
        sodiumLoader: () async =>
            throw StateError('No crypto needed before receive'),
      ),
      shareId: '00112233-4455-4677-8899-aabbccddeeff',
      secrets: secrets,
      owner: guest,
      ownerReader: () => authority.read(null),
      now: () => now,
    );
    final start = continuation.begin(reception, EntryShareAccountAction.login);
    await tester.pump();
    expect(await start, true);
    router = createRouter(auth, sharingAccount: continuation);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      continuation.dispose();
      ingress.dispose();
      final closing = Future.wait([
        reception.close(),
        auth.close(),
        loginEvents.close(),
      ]);
      await tester.pump();
      await closing;
      keys.clear();
      await getIt.reset();
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(polish ? 'pl' : 'en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Roboto',
            brightness: polish ? Brightness.dark : Brightness.light,
            colorScheme: polish
                ? const ColorScheme.dark(primary: AppColors.brandRed)
                : const ColorScheme.light(primary: AppColors.brandRed),
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
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    continuation.dispose();
    await tester.pump();
  }

  void loginSuccess() {
    token =
        'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'recipient', 'organization_id': 'recipient-org', 'authz_ver': '7'}))).replaceAll('=', '')}.synthetic';
    loginEvents.add(
      LoginSuccess(masterKey: Uint8List(32), privateKey: Uint8List(32)),
    );
  }

  testWidgets(
    'production login listener and AuthBloc return to the clean sharing route',
    (tester) async {
      await mount(tester);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Cancel reception'), findsOneWidget);
      loginSuccess();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.toString(), '/share');
      expect(find.byType(EntryShareReceiverPlaceholder), findsOneWidget);
      expect(auth.state, isA<AuthAuthenticated>());
      expect(continuation.ready, true);
      final owner = (await authority.read('recipient'))!;
      final claim = continuation.take(
        version: ingress.version,
        owner: owner,
        ownerReader: () => authority.read('recipient'),
      );
      await tester.pump();
      final resumed = (await claim)!;
      expect(resumed.lifetime, same(reception.lifetime));
      expect(resumed.state.phase, EntryShareReceptionPhase.welcome);
      verifyZeroInteractions(remote);
      await resumed.close();
      await finish(tester);
    },
  );

  testWidgets('production router waits on independent authority after login', (
    tester,
  ) async {
    await mount(tester);
    final pending = Completer<EntryShareRecipientOwner?>();
    ownerReader = (_) => pending.future;
    loginSuccess();
    await tester.pumpAndSettle();
    expect(auth.state, isA<AuthAuthenticated>());
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(continuation.ready, false);
    pending.complete(await authority.read('recipient'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(), '/share');
    expect(continuation.ready, true);
    await finish(tester);
  });

  testWidgets(
    'cancel confirmation preserves login input and does not revoke link or account',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      final input = find.byType(EditableText).first;
      await tester.enterText(input, 'draft@example.invalid');
      final originalInput = tester.state(input);
      await tester.tap(find.text('Cancel reception'));
      await tester.pumpAndSettle();
      expect(continuation.active, true);
      await tester.tap(find.text('Keep reception'));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(EditableText).first),
        same(originalInput),
      );
      await tester.tap(find.text('Cancel reception'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard reception'));
      await tester.pumpAndSettle();
      expect(continuation.active, false);
      expect(secrets.key, everyElement(0));
      expect(find.text('Cancel reception'), findsNothing);
      expect(find.text('draft@example.invalid'), findsOneWidget);
      expect(
        tester.state(find.byType(EditableText).first),
        same(originalInput),
      );
      expect(router.routeInformationProvider.value.uri.path, '/login');
      verify(() => remote.close()).called(1);
      verifyNoMoreInteractions(remote);
      verifyNever(() => repository.logout());
      await finish(tester);
    },
  );

  testWidgets(
    'original expiry removes pending cancellation without extending reception',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Cancel reception'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 16));
      await tester.pump(const Duration(minutes: 16));
      await tester.pumpAndSettle();
      expect(find.text('Discard reception'), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(continuation.active, false);
      expect(secrets.key, everyElement(0));
      await finish(tester);
    },
  );

  for (final polish in [false, true]) {
    testWidgets(
      'account cancel layout remains usable with keyboard: pl=$polish',
      (tester) async {
        await mount(tester, polish: polish);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EntryShareAccountFrame)),
        )!;
        await tester.tap(find.text(l10n.sharingCancelReception));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bannerScroll = find
            .descendant(
              of: find.byType(EntryShareAccountFrame),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text(l10n.sharingKeepReception),
          60,
          scrollable: find.descendant(
            of: bannerScroll,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        final dir = Platform.environment['PALLADIN_SHARING_VISUAL_DIR'];
        if (dir != null) {
          await tester.runAsync(() async {
            final boundary =
                screenshot.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/account-cancel-${polish ? 'pl-dark-320-150' : 'en-light-390'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text(l10n.sharingKeepReception));
        await tester.pumpAndSettle();
        expect(continuation.active, true);
        await tester.ensureVisible(find.text(l10n.continueWithEmail));
        await tester.tap(find.text(l10n.continueWithEmail));
        await tester.pumpAndSettle();
        final email = find.byType(EditableText).first;
        await tester.ensureVisible(email);
        await tester.enterText(email, 'recipient@example.invalid');
        await tester.pumpAndSettle();
        expect(find.text('recipient@example.invalid'), findsOneWidget);
        final inputBounds = tester.getRect(email);
        expect(inputBounds.top, greaterThanOrEqualTo(0));
        expect(
          inputBounds.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height - 200),
        );
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }
}
