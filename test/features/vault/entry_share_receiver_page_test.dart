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
import 'package:mobile_palladin/core/crypto/sodium_provider.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_recipient_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_share_copy_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_copy_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_copy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_reception.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_reception_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_account_continuation.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_receiver_page.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_field_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Remote extends Mock implements EntryShareRecipientDatasource {}

class _CopyRemote extends Mock implements EntryShareCopyDatasource {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const EntryShareRecipientOwner _guest = (
  principalId: null,
  organizationId: null,
  authorizationGeneration: null,
  keyGeneration: 0,
);
const EntrySharingSession _member = (
  principalId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  organizationId: '11111111-1111-4111-8111-111111111111',
  authorizationGeneration: '7',
  keyGeneration: 1,
);
const _destination = '22222222-2222-4222-8222-222222222222';
const _newEntry = '33333333-3333-4333-8333-333333333333';
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
  EntryShareCopyService Function()? copyFactory;
  late Map<String, dynamic> copyVaultJson;
  late _CopyRemote copyRemote;
  late List<String> createdCopies;
  late CreatedVaultBundle destinationBundle;
  late Uint8List accountKey;

  setUpAll(() async {
    registerFallbackValue(CancelToken());
    registerFallbackValue(_member);
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
    SodiumProvider.debugOverride = sodium;
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
  tearDownAll(() => SodiumProvider.debugOverride = null);

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
    copyFactory = null;
    createdCopies = [];
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
    Future<void> Function(EntryShareAccountAction)? onAccount,
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
        builder: (_) => EntryShareReceiverPage(
          cubit: cubit,
          copyServiceFactory: copyFactory,
          onAccount: onAccount,
        ),
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

  Future<void> enableSaving(
    WidgetTester tester, {
    bool locked = false,
    bool verified = true,
    int permissions = Permissions.vaultManage,
  }) async {
    await cubit.close();
    owner = _member;
    accountKey = sodium.randombytes.buf(32);
    final authState = AuthAuthenticated(
      userId: _member.principalId,
      isOnboarded: true,
      isVaultLocked: locked,
      emailVerified: verified,
      permissions: permissions,
      privateKey: locked ? null : accountKey,
    );
    when(() => auth.state).thenReturn(authState);
    secrets = EntryShareSecrets(
      key: VaultProtocolBytes.hex(_fixture['keyHex']),
      accessToken: Uint8List(32)..fillRange(0, 32, 7),
    );
    cubit = EntryShareReceptionCubit(
      remote: remote,
      crypto: EntryShareCryptoService(sodiumLoader: () async => sodium),
      shareId: _shareId,
      secrets: secrets,
      owner: _member,
      ownerReader: () async => owner,
      now: () => _now,
    );
    await tester.runAsync(() async {
      destinationBundle =
          await VaultCryptoService(
            sodiumLoader: () async => sodium,
          ).createVaultBundle(
            organizationId: _member.organizationId,
            memberId: _member.principalId,
            memberKeyVersion: 1,
            vaultId: _destination,
            memberPrivateKey: accountKey,
            name: 'Personal vault',
            grantMode: GrantMode.granular,
          );
    });
    addTearDown(() {
      accountKey.fillRange(0, accountKey.length, 0);
      destinationBundle.vaultKey.fillRange(
        0,
        destinationBundle.vaultKey.length,
        0,
      );
      destinationBundle.vaultDiscoveryKey.fillRange(
        0,
        destinationBundle.vaultDiscoveryKey.length,
        0,
      );
    });
    copyVaultJson =
        jsonDecode(
              jsonEncode({
                'id': _destination,
                'organizationId': _member.organizationId,
                'memberKeyGeneration': 1,
                'metadataRevision': '1',
                'memberVaultKey': {
                  'wrappedVaultKey': destinationBundle.request.creatorVaultKey
                      .toJson(),
                },
                'memberVaultMetadata': destinationBundle
                    .request
                    .memberVaultMetadata
                    .toJson(),
                'currentKeyEpoch': destinationBundle.request.currentKeyEpoch
                    .toJson(),
                'discoveryKey': destinationBundle.request.discoveryKey.toJson(),
              }),
            )
            as Map<String, dynamic>;
    copyRemote = _CopyRemote();
    when(
      () => copyRemote.vault(any(), any(), any()),
    ).thenAnswer((_) async => copyVaultJson);
    when(() => copyRemote.vaults(any(), any(), any())).thenAnswer(
      (_) async => {
        'vaults': [
          Map<String, dynamic>.from(copyVaultJson)
            ..remove('organizationId')
            ..remove('metadataRevision'),
        ],
        'total': 1,
      },
    );
    when(
      () => copyRemote.challenge(any(), any(), any()),
    ).thenAnswer((_) async => _newEntry);
    when(() => copyRemote.create(any(), any(), any(), any())).thenAnswer((
      call,
    ) async {
      createdCopies.add(call.positionalArguments[1] as String);
    });
    copyFactory = () => EntryShareCopyService(
      remote: copyRemote,
      vaultCrypto: VaultCryptoService(sodiumLoader: () async => sodium),
      entryCrypto: EntryV2CryptoService(sodiumLoader: () async => sodium),
      autoFill: AutoFillMutationNotifier(),
    );
  }

  Future<void> chooseDestination(
    WidgetTester tester, {
    String name = 'Personal vault',
  }) async {
    final dropdown = find.descendant(
      of: find.byKey(const ValueKey('sharing-copy-vault')),
      matching: find.byType(DropdownButton<String>),
    );
    await tester.scrollUntilVisible(
      dropdown,
      -180,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(dropdown.hitTestable(), findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> completeCopy(
    WidgetTester tester, {
    String vaultName = 'Personal vault',
  }) async {
    await chooseDestination(tester, name: vaultName);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sharing-copy-credential.username')),
      180,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('sharing-copy-credential.username')),
        matching: find.byType(TextField),
      ),
      '  recipient user  ',
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveCopy(WidgetTester tester, {bool retry = false}) async {
    await tap(tester, retry ? 'Retry same request' : 'Save a copy');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'received copy saves through mounted form once with fresh destination encryption',
    (tester) async {
      await enableSaving(tester);
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      expect(createdCopies, isEmpty);
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Save a copy'),
            )
            .onPressed,
        isNull,
      );
      await completeCopy(tester);
      await capture(tester, 'copy-en-light-390');
      await saveCopy(tester);
      expect(createdCopies.length, 1);
      expect(
        find.text(
          'Copy saved in your vault. It will not sync with the original.',
        ),
        findsOneWidget,
      );
      final request = jsonDecode(createdCopies.single) as Map<String, dynamic>;
      await tester.runAsync(() async {
        final plaintext =
            await EntryV2CryptoService(
              sodiumLoader: () async => sodium,
            ).openMemberSecret(
              entryKey: request['entryKey'],
              memberSecret: request['memberSecret'],
              vaultKey: destinationBundle.vaultKey,
            );
        expect((plaintext['content'] as Map)['password'], 'fixture-only');
        expect((plaintext['content'] as Map)['username'], '  recipient user  ');
        expect(plaintext['discoverable'], isFalse);
      });
      await tap(tester, 'Back to received entry');
      expect(find.text('Save a copy'), findsNothing);
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verify(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      await finish(tester);
    },
  );

  testWidgets(
    'ambiguous mounted save permits only exact encrypted retry, not another receipt',
    (tester) async {
      await enableSaving(tester);
      when(() => copyRemote.create(any(), any(), any(), any())).thenAnswer((
        call,
      ) async {
        createdCopies.add(call.positionalArguments[1] as String);
        if (createdCopies.length == 1) {
          throw const EntryShareCopyException(EntryShareCopyError.request);
        }
      });
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await completeCopy(tester);
      final controllers = tester
          .widgetList<OnboardingTextField>(find.byType(OnboardingTextField))
          .map((field) => field.controller)
          .toList();
      await saveCopy(tester);
      expect(find.text('Retry same request'), findsOneWidget);
      expect(find.text('Back to received entry'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        controllers.map((controller) => controller.text),
        everyElement(isEmpty),
      );
      await saveCopy(tester, retry: true);
      expect(createdCopies.length, 2);
      expect(createdCopies.first, createdCopies.last);
      verify(() => copyRemote.challenge(any(), any(), any())).called(1);
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      await finish(tester);
    },
  );

  testWidgets(
    'cancel before saving returns to received copy without challenge or redelivery',
    (tester) async {
      await enableSaving(tester);
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await tester.scrollUntilVisible(
        find.text('Back to received entry'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, 'Back to received entry');
      expect(find.text('Save a copy'), findsOneWidget);
      expect(createdCopies, isEmpty);
      verifyNever(() => copyRemote.challenge(any(), any(), any()));
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      await finish(tester);
    },
  );

  testWidgets(
    'background during destination lookup cancels request and drops late list',
    (tester) async {
      await enableSaving(tester);
      final read = Completer<Map<String, dynamic>>();
      CancelToken? token;
      when(() => copyRemote.vaults(any(), any(), any())).thenAnswer((call) {
        token = call.positionalArguments[2] as CancelToken;
        return read.future;
      });
      await mount(tester);
      await receive(tester);
      await tester.tap(find.text('Save a copy'));
      await tester.pump();
      expect(token, isNotNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(token!.isCancelled, isTrue);
      read.complete({
        'vaults': [copyVaultJson],
        'total': 1,
      });
      await tester.pumpAndSettle();
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      expect(find.byType(TextField), findsNothing);
      expect(createdCopies, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('lock removes copy controls and entered completion', (
    tester,
  ) async {
    await enableSaving(tester);
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    await completeCopy(tester);
    final controllers = tester
        .widgetList<OnboardingTextField>(find.byType(OnboardingTextField))
        .map((field) => field.controller)
        .toList();
    authEvents.add(
      (auth.state as AuthAuthenticated).copyWith(
        isVaultLocked: true,
        clearKeys: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controllers.map((controller) => controller.text),
      everyElement(isEmpty),
    );
    expect(find.byType(TextField), findsNothing);
    expect(createdCopies, isEmpty);
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    await finish(tester);
  });

  for (final mode in ['locked', 'unverified', 'no permission']) {
    testWidgets('$mode recipient cannot start destination save', (
      tester,
    ) async {
      await enableSaving(
        tester,
        locked: mode == 'locked',
        verified: mode != 'unverified',
        permissions: mode == 'no permission' ? 0 : Permissions.vaultManage,
      );
      await mount(tester);
      await receive(tester);
      expect(find.text('Save a copy'), findsNothing);
      expect(createdCopies, isEmpty);
      await finish(tester);
    });
  }

  testWidgets('unreadable destination is isolated without hiding usable vaults', (
    tester,
  ) async {
    await enableSaving(tester);
    final corrupt =
        jsonDecode(jsonEncode(copyVaultJson)) as Map<String, dynamic>;
    corrupt['memberVaultKey']['wrappedVaultKey']['descriptor']['scope']['memberId'] =
        _destination;
    when(() => copyRemote.vaults(any(), any(), any())).thenAnswer(
      (_) async => {
        'vaults': [corrupt, copyVaultJson],
        'total': 2,
      },
    );
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    final warning = find.text(
      'Some vaults could not be decrypted and are not offered as destinations. Other vaults remain available.',
    );
    await tester.ensureVisible(warning);
    expect(warning, findsOneWidget);
    await completeCopy(tester);
    await tap(tester, 'Save a copy');
    expect(createdCopies, hasLength(1));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('empty destination does not auto-create or enable save', (
    tester,
  ) async {
    await enableSaving(tester);
    when(
      () => copyRemote.vaults(any(), any(), any()),
    ).thenAnswer((_) async => {'vaults': [], 'total': 0});
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    expect(
      find.text('There is no available destination vault for this account.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<PrimaryButton>(
            find.widgetWithText(PrimaryButton, 'Save a copy'),
          )
          .onPressed,
      isNull,
    );
    expect(createdCopies, isEmpty);
    expect(find.text('Create my personal vault'), findsNothing);
    await finish(tester);
  });

  Future<List<String>> enablePersonalVaultCreation(WidgetTester tester) async {
    await enableSaving(
      tester,
      permissions: Permissions.vaultManage | Permissions.vaultCreate,
    );
    final posts = <String>[];
    when(
      () => copyRemote.memberContext(any(), any()),
    ).thenAnswer((_) async => (memberId: _member.principalId, keyVersion: 1));
    when(
      () => copyRemote.vaultChallenge(any(), any()),
    ).thenAnswer((_) async => _destination);
    when(() => copyRemote.vaults(any(), any(), any())).thenAnswer(
      (_) async => {
        'vaults': posts.isEmpty ? [] : [copyVaultJson],
        'total': posts.isEmpty ? 0 : 1,
      },
    );
    when(() => copyRemote.createDefaultVault(any(), any(), any())).thenAnswer((
      call,
    ) async {
      final encoded = call.positionalArguments[0] as String;
      posts.add(encoded);
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      copyVaultJson = {
        'id': _destination,
        'organizationId': _member.organizationId,
        'memberKeyGeneration': 1,
        'metadataRevision': '1',
        'memberVaultKey': data['creatorVaultKey'],
        'memberVaultMetadata': data['memberVaultMetadata'],
        'currentKeyEpoch': data['currentKeyEpoch'],
        'discoveryKey': data['discoveryKey'],
      };
    });
    return posts;
  }

  testWidgets(
    'explicit personal vault creation keeps the receipt and requires selection before save',
    (tester) async {
      final vaultPosts = await enablePersonalVaultCreation(tester);
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      expect(vaultPosts, isEmpty);
      await capture(tester, 'first-vault-en-light-390');
      await tap(tester, 'Create my personal vault');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(vaultPosts, hasLength(1));
      expect(createdCopies, isEmpty);
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Save a copy'),
            )
            .onPressed,
        isNull,
      );
      await completeCopy(tester, vaultName: 'Personal');
      await saveCopy(tester);
      expect(createdCopies, hasLength(1));
      await tester.runAsync(() async {
        final opened =
            await VaultCryptoService(
              sodiumLoader: () async => sodium,
            ).openVaultProjection(
              json: copyVaultJson,
              memberPrivateKey: accountKey,
            );
        try {
          final entry =
              jsonDecode(createdCopies.single) as Map<String, dynamic>;
          final secret =
              await EntryV2CryptoService(
                sodiumLoader: () async => sodium,
              ).openMemberSecret(
                entryKey: entry['entryKey'],
                memberSecret: entry['memberSecret'],
                vaultKey: opened.vaultKey,
              );
          expect((secret['content'] as Map)['password'], 'fixture-only');
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
      verify(
        () => remote.receive(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verify(
        () => remote.confirmDisplay(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'failed personal vault creation retries the same ciphertext without another receipt',
    (tester) async {
      await enablePersonalVaultCreation(tester);
      final attempts = <String>[];
      when(() => copyRemote.createDefaultVault(any(), any(), any())).thenAnswer(
        (call) async {
          attempts.add(call.positionalArguments[0] as String);
          if (attempts.length == 1) {
            throw const EntryShareCopyException(EntryShareCopyError.request);
          }
        },
      );
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await tap(tester, 'Create my personal vault');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The vault could not be created. Retry here while this reception is still available.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Create my personal vault');
      expect(attempts, hasLength(2));
      expect(attempts[1], attempts[0]);
      verify(() => copyRemote.vaultChallenge(any(), any())).called(1);
      expect(createdCopies, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('failed refresh after vault creation never repeats the write', (
    tester,
  ) async {
    final posts = await enablePersonalVaultCreation(tester);
    var failRefresh = true;
    when(() => copyRemote.vaults(any(), any(), any())).thenAnswer((_) async {
      if (posts.isNotEmpty && failRefresh) {
        throw const EntryShareCopyException(EntryShareCopyError.request);
      }
      return {
        'vaults': posts.isEmpty ? [] : [copyVaultJson],
        'total': posts.isEmpty ? 0 : 1,
      };
    });
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    await tap(tester, 'Create my personal vault');
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(posts, hasLength(1));
    expect(find.text('Create my personal vault'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    failRefresh = false;
    await tap(tester, 'Refresh');
    await chooseDestination(tester, name: 'Personal');
    expect(posts, hasLength(1));
    expect(createdCopies, isEmpty);
    verify(
      () =>
          remote.receive(any(), any(), cancelToken: any(named: 'cancelToken')),
    ).called(1);
    await finish(tester);
  });

  testWidgets(
    'default vault conflict offers the authoritative existing destination',
    (tester) async {
      await enablePersonalVaultCreation(tester);
      var conflicted = false;
      when(() => copyRemote.createDefaultVault(any(), any(), any())).thenAnswer(
        (_) async {
          conflicted = true;
          throw const EntryShareCopyException(
            EntryShareCopyError.request,
            statusCode: 409,
          );
        },
      );
      when(() => copyRemote.vaults(any(), any(), any())).thenAnswer(
        (_) async => {
          'vaults': conflicted ? [copyVaultJson] : [],
          'total': conflicted ? 1 : 0,
        },
      );
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await tap(tester, 'Create my personal vault');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      await chooseDestination(tester);
      expect(find.text('Create my personal vault'), findsNothing);
      expect(createdCopies, isEmpty);
      verify(
        () => copyRemote.createDefaultVault(any(), any(), any()),
      ).called(1);
      await finish(tester);
    },
  );

  for (final transition in ['background', 'lock']) {
    testWidgets(
      '$transition during personal vault creation rejects late success',
      (tester) async {
        await enablePersonalVaultCreation(tester);
        final write = Completer<void>();
        CancelToken? token;
        when(
          () => copyRemote.createDefaultVault(any(), any(), any()),
        ).thenAnswer((call) {
          token = call.positionalArguments[2] as CancelToken;
          return write.future;
        });
        await mount(tester);
        await receive(tester);
        await tap(tester, 'Save a copy');
        await tester.tap(find.text('Create my personal vault'));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        expect(token, isNotNull);
        final controllers = tester
            .widgetList<OnboardingTextField>(find.byType(OnboardingTextField))
            .map((field) => field.controller)
            .toList();
        if (transition == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else {
          authEvents.add(
            (auth.state as AuthAuthenticated).copyWith(
              isVaultLocked: true,
              clearKeys: true,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(token!.isCancelled, true);
        expect(
          controllers.map((controller) => controller.text),
          everyElement(isEmpty),
        );
        write.complete();
        await tester.pumpAndSettle();
        expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
        expect(find.byType(TextField), findsNothing);
        expect(createdCopies, isEmpty);
        verify(() => copyRemote.vaults(any(), any(), any())).called(1);
        await finish(tester);
      },
    );
  }

  testWidgets(
    'first personal vault action fits Polish narrow large-text layout',
    (tester) async {
      final posts = await enablePersonalVaultCreation(tester);
      await mount(tester, language: 'pl', dark: true, width: 320, scale: 1.5);
      await tap(tester, 'Otwórz udostępnienie');
      await tap(tester, 'Odbierz wpis');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Zapisz kopię');
      final create = find.text('Utwórz mój osobisty sejf');
      await tester.scrollUntilVisible(
        create,
        180,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pumpAndSettle();
      expect(create.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'first-vault-pl-dark-320-150');
      await tap(tester, 'Utwórz mój osobisty sejf');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      await chooseDestination(tester, name: 'Osobisty');
      expect(createdCopies, isEmpty);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'missing completion stays inline and does not request a challenge',
    (tester) async {
      await enableSaving(tester);
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await chooseDestination(tester);
      await tap(tester, 'Save a copy');
      await tester.ensureVisible(find.text('Complete this required field.'));
      await tester.pumpAndSettle();
      expect(find.text('Complete this required field.'), findsOneWidget);
      verifyNever(() => copyRemote.challenge(any(), any(), any()));
      await finish(tester);
    },
  );

  testWidgets(
    'copy form remains usable in narrow Polish dark layout with larger text',
    (tester) async {
      await enableSaving(tester);
      await mount(tester, language: 'pl', dark: true, width: 320, scale: 1.5);
      await tap(tester, 'Otwórz udostępnienie');
      await tap(tester, 'Odbierz wpis');
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Zapisz kopię');
      expect(tester.takeException(), isNull);
      await capture(tester, 'copy-pl-dark-320-150');
      await chooseDestination(tester);
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final username = find.byKey(
        const ValueKey('sharing-copy-credential.username'),
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
      await tester.enterText(
        find.descendant(of: username, matching: find.byType(TextField)),
        'odbiorca',
      );
      await tester.ensureVisible(username);
      await tester.pumpAndSettle();
      expect(find.text('odbiorca'), findsOneWidget);
      expect(
        tester.getBottomRight(username).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(find.widgetWithText(PrimaryButton, 'Zapisz kopię'))
              .dy,
        ),
      );
      expect(
        find.widgetWithText(PrimaryButton, 'Zapisz kopię'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'copy-keyboard-pl-dark-320-150');
      tester.view.resetViewInsets();
      await finish(tester);
    },
  );

  testWidgets(
    'destination lookup failure can retry inside the original reception',
    (tester) async {
      await enableSaving(tester);
      var attempts = 0;
      when(() => copyRemote.vaults(any(), any(), any())).thenAnswer((_) async {
        if (attempts++ == 0) {
          throw const EntryShareCopyException(EntryShareCopyError.request);
        }
        return {
          'vaults': [copyVaultJson],
          'total': 1,
        };
      });
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      expect(attempts, 1);
      await tap(tester, 'Refresh');
      expect(attempts, 2);
      await completeCopy(tester);
      await saveCopy(tester);
      expect(createdCopies.length, 1);
      await finish(tester);
    },
  );

  testWidgets('invalid title stays editable and never reaches create', (
    tester,
  ) async {
    await enableSaving(tester);
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    await completeCopy(tester);
    final title = find.descendant(
      of: find.byKey(const ValueKey('sharing-copy-title')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(title);
    await tester.enterText(title, ' ');
    await tap(tester, 'Save a copy');
    expect(createdCopies, isEmpty);
    verifyNever(() => copyRemote.challenge(any(), any(), any()));
    expect(
      find.text(
        'Enter a name of 1–200 characters. The received name is never shortened automatically.',
      ),
      findsOneWidget,
    );
    await tester.enterText(title, 'My independent copy');
    await saveCopy(tester);
    expect(createdCopies.length, 1);
    await finish(tester);
  });

  testWidgets(
    'background during canonical create cancels request and rejects late success',
    (tester) async {
      await enableSaving(tester);
      final barrier = Completer<void>();
      CancelToken? requestToken;
      when(() => copyRemote.create(any(), any(), any(), any())).thenAnswer((
        call,
      ) {
        requestToken = call.positionalArguments[3] as CancelToken;
        createdCopies.add(call.positionalArguments[1] as String);
        return barrier.future;
      });
      await mount(tester);
      await receive(tester);
      await tap(tester, 'Save a copy');
      await completeCopy(tester);
      await tester.tap(find.widgetWithText(PrimaryButton, 'Save a copy'));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(requestToken, isNotNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(requestToken!.isCancelled, isTrue);
      barrier.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Copy saved in your vault. It will not sync with the original.',
        ),
        findsNothing,
      );
      expect(find.text('Save a copy'), findsNothing);
      expect(createdCopies.length, 1);
      expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
      await finish(tester);
    },
  );

  testWidgets('original reception expiry discards an unfinished save form', (
    tester,
  ) async {
    await enableSaving(tester);
    await mount(tester);
    await receive(tester);
    await tap(tester, 'Save a copy');
    await completeCopy(tester);
    final controllers = tester
        .widgetList<OnboardingTextField>(find.byType(OnboardingTextField))
        .map((field) => field.controller)
        .toList();
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(cubit.state.phase, EntryShareReceptionPhase.unavailable);
    expect(
      controllers.map((controller) => controller.text),
      everyElement(isEmpty),
    );
    expect(createdCopies, isEmpty);
    await finish(tester);
  });

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

  for (final polish in [false, true]) {
    testWidgets(
      'optional account CTA keeps guest reception accessible: pl=$polish',
      (tester) async {
        final actions = <EntryShareAccountAction>[];
        await mount(
          tester,
          language: polish ? 'pl' : 'en',
          dark: polish,
          width: polish ? 320 : 390,
          scale: polish ? 1.5 : 1,
          onAccount: (action) async {
            actions.add(action);
          },
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EntryShareReceiverPage)),
        )!;
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          polish ? 'account-pl-dark-320-150' : 'account-en-light-390',
        );
        for (final label in [l10n.sharingRegister, l10n.sharingLogin]) {
          await tester.scrollUntilVisible(
            find.text(label),
            160,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tap(tester, label);
        }
        expect(actions, [
          EntryShareAccountAction.register,
          EntryShareAccountAction.login,
        ]);
        expect(cubit.state.phase, EntryShareReceptionPhase.welcome);
        verifyNever(
          () =>
              remote.open(any(), any(), cancelToken: any(named: 'cancelToken')),
        );
        await tap(tester, polish ? 'Otwórz udostępnienie' : 'Open sharing');
        expect(cubit.state.phase, EntryShareReceptionPhase.verification);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

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
