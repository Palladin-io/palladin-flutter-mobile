import 'dart:async';
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
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/core/widgets/accent_button.dart';
import 'package:mobile_palladin/core/widgets/app_action_footer.dart';
import 'package:mobile_palladin/core/widgets/app_toggle.dart';
import 'package:mobile_palladin/core/widgets/app_form_section.dart';
import 'package:mobile_palladin/core/widgets/primary_button.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/onboarding/presentation/widgets/onboarding_text_field.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_list.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_share_creation_page.dart';
import 'package:mobile_palladin/features/vault/presentation/pages/entry_sharing_tab.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_creation_form.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

class _Remote extends Mock implements EntrySharingRemoteDatasource {}

class _Local extends Mock implements LocalCurrentEntryService {}

class _Authority extends Mock implements MemberSyncSessionAuthorityProvider {}

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Vaults extends MockCubit<VaultListState> implements VaultListCubit {}

const _organizationId = '11112233-4455-4677-8899-aabbccddeeff';
const _vaultId = '22112233-4455-4677-8899-aabbccddeeff';
const _entryId = '33112233-4455-4677-8899-aabbccddeeff';
const _shareId = '00112233-4455-4677-8899-aabbccddeeff';
final _entry = EntryEntity(
  id: _entryId,
  vaultId: _vaultId,
  label: 'Synthetic entry',
  type: EntryType.credential,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  currentRevision: '1',
);
CanonicalEntrySnapshot _source() => CanonicalEntrySnapshot(
  entry: {
    'id': _entryId,
    'vaultId': _vaultId,
    'organizationId': _organizationId,
    'currentRevision': '1',
  },
  secret: {'entryType': 1, 'memberLabel': 'Synthetic entry'},
  payload: {
    'username': 'synthetic-user',
    'password': 'synthetic-password',
    'notes': 'private notes',
  },
);

void main() {
  late SodiumSumo sodium;
  late _Remote remote;
  late _Local local;
  late _Auth auth;
  late _Vaults vaults;
  late StreamController<AuthState> authEvents;
  late AuthAuthenticated unlocked;
  final requests = <EntryShareCreationRequest>[];
  final copiedKeys = <Uint8List>[];
  String? clipboard;
  final nativeShares = <Map<dynamic, dynamic>>[];
  setUpAll(() async {
    final visualFont = Platform.environment['PALLADIN_SHARING_VISUAL_FONT'];
    if (visualFont != null) {
      final bytes = await File(visualFont).readAsBytes();
      for (final family in ['SharingVisualInter', 'Roboto', 'Ahem']) {
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    registerFallbackValue(CancelToken());
    registerFallbackValue(Uint8List(32));
    registerFallbackValue(_entry);
    registerFallbackValue(
      EntryShareCreationRequest(
        shareId: _shareId,
        sourceRevision: '1',
        expiresAt: '2026-09-20T12:00:00Z',
        options: EntryShareCreationOptions.fromInput(
          recipientEmail: 'test@example.test',
        ),
        accessToken: 'synthetic',
        packet: const EntryShareCiphertext(
          nonce: 'synthetic',
          ciphertext: 'synthetic',
        ),
      ),
    );
    final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
    sodium = configured != null || Platform.isLinux
        ? await sodium_ffi.SodiumSumoInit.init(
            () => DynamicLibrary.open(configured ?? 'libsodium.so'),
          )
        : await SodiumSumoInit.init();
  });
  setUp(() {
    remote = _Remote();
    local = _Local();
    auth = _Auth();
    vaults = _Vaults();
    when(() => vaults.state).thenReturn(const VaultListInitial());
    getIt.registerSingleton<VaultListCubit>(vaults);
    authEvents = StreamController<AuthState>();
    unlocked = AuthAuthenticated(
      userId: 'member',
      isOnboarded: true,
      isVaultLocked: false,
      privateKey: Uint8List.fromList(List.filled(32, 9)),
      permissions: 8,
    );
    whenListen(auth, authEvents.stream, initialState: unlocked);
    requests.clear();
    copiedKeys.clear();
    clipboard = null;
    when(
      () => local.reveal(
        expected: any(named: 'expected'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((invocation) async {
      copiedKeys.add(invocation.namedArguments[#memberPrivateKey] as Uint8List);
      return _source();
    });
    when(
      () => remote.challenge(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => const EntryShareCreationChallenge(
        shareId: _shareId,
        sourceRevision: '1',
        expiresAt: '2026-09-20T12:00:00Z',
      ),
    );
    when(
      () => remote.create(
        any(),
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((invocation) async {
      requests.add(
        invocation.positionalArguments[2] as EntryShareCreationRequest,
      );
    });
    final authority = _Authority();
    when(
      () => remote.list(
        any(),
        any(),
        cursor: any(named: 'cursor'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => EntrySharesPage(items: [], nextCursor: null));
    when(authority.current).thenAnswer(
      (_) async => const MemberSyncSessionAuthority(
        principalId: 'member',
        organizationId: _organizationId,
        organizationMembershipGeneration: '1',
        offlinePolicy: '1h',
        offlinePolicyVersion: 1,
      ),
    );
    getIt.registerSingleton<EntrySharingRemoteDatasource>(remote);
    getIt.registerSingleton<LocalCurrentEntryService>(local);
    getIt.registerSingleton<EntryShareCryptoService>(
      EntryShareCryptoService(sodiumLoader: () async => sodium),
    );
    getIt.registerSingleton<MemberSyncSessionAuthorityProvider>(authority);
    getIt.registerSingleton<VaultSessionStore>(VaultSessionStore());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    nativeShares.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
            expect(call.method, 'share');
            nativeShares.add(call.arguments as Map);
            return 'dev.fluttercommunity.plus/share/dismissed';
          },
        );
  });
  tearDown(() async {
    await authEvents.close();
    await auth.close();
    await getIt.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          null,
        );
  });
  Future<void> pump(
    WidgetTester tester, {
    String locale = 'en',
    Brightness brightness = Brightness.light,
    double scale = 1,
    String origin = 'https://stage.palladin.io',
    bool fromList = false,
  }) async {
    getIt.registerSingleton<EnvConfig>(
      EnvConfig.staging(
        apiBaseUrl: 'https://stage.example.test',
        sharingWebOrigin: origin,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: ThemeData(
          brightness: brightness,
          fontFamily:
              Platform.environment.containsKey('PALLADIN_SHARING_VISUAL_FONT')
              ? 'SharingVisualInter'
              : null,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('sharing-visual'),
            child: child!,
          ),
        ),
        home: BlocProvider<AuthBloc>.value(
          value: auth,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => fromList
                    ? Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => BlocProvider<AuthBloc>.value(
                            value: auth,
                            child: Scaffold(
                              body: EntrySharingTab(
                                entry: _entry,
                                active: true,
                              ),
                            ),
                          ),
                        ),
                      )
                    : EntryShareCreationPage.push(context, _entry),
                child: const Text('Open sharing'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sharing'));
    await tester.pumpAndSettle();
    if (fromList) {
      await tester.tap(
        find.widgetWithText(PrimaryButton, 'Create sharing link'),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['PALLADIN_SHARING_VISUAL_DIR'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('sharing-visual')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  Finder toggle(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
  Finder input(String label) => find.widgetWithText(OnboardingTextField, label);
  Future<void> visible(WidgetTester tester, Finder finder) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    // Expanded security fields can occupy the drag starting point. Use the
    // owned list position rather than accidentally dragging an editable field.
    for (
      var attempt = 0;
      finder.evaluate().isEmpty && attempt < 50;
      attempt++
    ) {
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(
        (position.pixels + 200).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    await visible(tester, input(label));
    await tester.enterText(
      find.descendant(of: input(label), matching: find.byType(TextField)),
      value,
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseToggle(WidgetTester tester, String label) async {
    await visible(tester, toggle(label));
    await tester.tap(toggle(label));
    await tester.pumpAndSettle();
  }

  Future<void> section(WidgetTester tester, String label) async {
    final header = find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is AppFormSection && widget.label == label,
          ),
          matching: find.byType(InkWell),
        )
        .first;
    await visible(tester, header);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Future<void> create(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(PrimaryButton, 'Create sharing link'));
    await tester.pumpAndSettle();
  }

  Future<void> ready(WidgetTester tester) async {
    await section(tester, 'Recipient');
    await tester.tap(find.byType(DropdownButton<EntryShareRecipientMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only this person (email code)').last);
    await tester.pumpAndSettle();
    await enter(
      tester,
      'Recipient emails (comma-separated)',
      ' recipient@example.test ',
    );
  }

  testWidgets(
    'root-navigator creation resolves the source Vault from the shared cache',
    (tester) async {
      when(() => vaults.state).thenReturn(
        VaultListLoaded([
          VaultEntity(
            id: _vaultId,
            name: 'Personal vault',
            grantMode: GrantMode.granular,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            entryCount: 1,
            activeGrantCount: 0,
            memberCount: 1,
          ),
        ]),
      );
      await pump(tester, fromList: true);
      expect(find.text('Personal vault'), findsOneWidget);
      expect(find.text('22112233…ddeeff'), findsNothing);
      expect(
        tester.getRect(find.text('Personal vault')).right,
        closeTo(tester.getRect(find.byType(AppFormSection).first).right, 0.01),
      );
      await dispose(tester);
    },
  );

  testWidgets('collapsed option chevrons share the right edge', (tester) async {
    await pump(tester);
    final sections = find.byType(AppFormSection);
    final right = tester.getRect(sections.first).right;
    for (final section in sections.evaluate()) {
      final chevron = find.descendant(
        of: find.byWidget(section.widget),
        matching: find.byIcon(Icons.expand_more),
      );
      expect(tester.getRect(chevron).right, closeTo(right, 0.01));
    }
    await dispose(tester);
  });

  testWidgets('footer paints through the device bottom safe area', (
    tester,
  ) async {
    tester.view.padding = FakeViewPadding(
      bottom: 34 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetPadding);
    await pump(tester);
    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final footer = tester.getRect(find.byType(EntryShareActionFooter));
    final button = tester.getRect(find.byType(PrimaryButton));
    expect(footer.bottom, closeTo(screenBottom, 0.01));
    expect(button.bottom, lessThanOrEqualTo(screenBottom - 34));
    expect(footer.left, 0);
    expect(
      footer.right,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    await dispose(tester);
  });

  testWidgets(
    'source keys are wiped; whole-entry defaults and four collapsed sections',
    (tester) async {
      await pump(tester);
      expect(copiedKeys.single, everyElement(0));
      expect(unlocked.privateKey, everyElement(9));
      expect(find.text('synthetic-password'), findsNothing);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
      );
      expect(find.byType(AppFormSection), findsNWidgets(4));
      expect(find.byType(AppToggle), findsOneWidget);
      expect(find.text('I have checked the selected fields'), findsNothing);
      expect(
        find.byType(DropdownButton<EntryShareRecipientMode>),
        findsNothing,
      );
      expect(find.text('Anyone with the link'), findsOneWidget);
      expect(find.text('Unlimited'), findsOneWidget);
      await section(tester, 'Recipient');
      await visible(
        tester,
        find.byType(DropdownButton<EntryShareRecipientMode>),
      );
      final dropdown = find.byType(DropdownButton<EntryShareRecipientMode>);
      expect(
        tester
            .widget<DropdownButton<EntryShareRecipientMode>>(dropdown)
            .style!
            .fontFamily,
        Theme.of(tester.element(dropdown)).textTheme.bodyMedium!.fontFamily,
      );
      expect(requests, isEmpty);
      await dispose(tester);
    },
  );

  testWidgets(
    'creates one named-recipient copy, opt-in Inbox and explicitly copies full link',
    (tester) async {
      await pump(tester);
      await ready(tester);
      await chooseToggle(tester, 'Notify me of the first receipt');
      await create(tester);
      expect(requests, hasLength(1));
      expect(requests.single.options.recipientEmail, 'recipient@example.test');
      expect(requests.single.options.protection, EntryShareProtection.none);
      expect(requests.single.options.notifyOnFirstReceipt, isTrue);
      expect(find.text('Your link is ready'), findsOneWidget);
      expect(find.byType(EntryShareCreationForm), findsNothing);
      expect(clipboard, isNull);
      await tester.tap(find.text('Copy sharing link'));
      await tester.pumpAndSettle();
      expect(
        clipboard,
        startsWith('https://stage.palladin.io/share/$_shareId#v=1&key='),
      );
      expect(find.text(clipboard!), findsNothing);
      final copiedLink = clipboard;
      await dispose(tester);
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(clipboard, copiedLink);
    },
  );

  testWidgets('selects and copies each recipient\'s independent link', (
    tester,
  ) async {
    const secondId = '778899aa-bbcc-4dde-8899-aabbccddeeff';
    var challengeCount = 0;
    when(
      () => remote.challenge(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer(
      (_) async => EntryShareCreationChallenge(
        shareId: challengeCount++ == 0 ? _shareId : secondId,
        sourceRevision: '1',
        expiresAt: '2026-09-20T12:00:00Z',
      ),
    );
    await pump(tester);
    await ready(tester);
    await enter(
      tester,
      'Recipient emails (comma-separated)',
      'first@example.test, second@example.test',
    );
    await create(tester);
    expect(requests.map((request) => request.options.recipientEmail), [
      'first@example.test',
      'second@example.test',
    ]);
    expect(find.text('Your link is ready'), findsOneWidget);
    await tester.tap(find.text('Copy sharing link'));
    await tester.pumpAndSettle();
    expect(
      clipboard,
      startsWith('https://stage.palladin.io/share/$_shareId#v=1&key='),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Your link is ready'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second@example.test').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy sharing link'));
    await tester.pumpAndSettle();
    expect(
      clipboard,
      startsWith('https://stage.palladin.io/share/$secondId#v=1&key='),
    );
    await dispose(tester);
  });

  testWidgets(
    'copy preserves exact partial-batch retry across a delivery roundtrip',
    (tester) async {
      const secondId = '778899aa-bbcc-4dde-8899-aabbccddeeff';
      var challengeCount = 0;
      when(
        () => remote.challenge(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => EntryShareCreationChallenge(
          shareId: challengeCount++ == 0 ? _shareId : secondId,
          sourceRevision: '1',
          expiresAt: '2026-09-20T12:00:00Z',
        ),
      );
      when(
        () => remote.create(
          any(),
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        requests.add(
          invocation.positionalArguments[2] as EntryShareCreationRequest,
        );
        if (requests.length == 2) throw const EntrySharingRequestException();
      });
      await pump(tester);
      await ready(tester);
      await enter(
        tester,
        'Recipient emails (comma-separated)',
        'first@example.test, second@example.test',
      );
      await create(tester);
      expect(requests, hasLength(2));
      expect(find.text('Retry same request'), findsOneWidget);
      expect(find.text('first@example.test'), findsOneWidget);
      expect(find.text('second@example.test'), findsNothing);
      expect(
        find.textContaining('Send each link to its matching recipient'),
        findsOneWidget,
      );

      await tester.tap(find.text('Copy sharing link'));
      await tester.pumpAndSettle();
      expect(
        clipboard,
        startsWith('https://stage.palladin.io/share/$_shareId#'),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Retry same request'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry same request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(requests[2], same(requests[1]));
      expect(challengeCount, 2);
      expect(find.text('Your link is ready'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'multi-recipient delivery roundtrip expires and cannot restore links',
    (tester) async {
      const secondId = '778899aa-bbcc-4dde-8899-aabbccddeeff';
      var challengeCount = 0;
      when(
        () => remote.challenge(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => EntryShareCreationChallenge(
          shareId: challengeCount++ == 0 ? _shareId : secondId,
          sourceRevision: '1',
          expiresAt: '2026-09-20T12:00:00Z',
        ),
      );
      await pump(tester);
      await ready(tester);
      await enter(
        tester,
        'Recipient emails (comma-separated)',
        'first@example.test, second@example.test',
      );
      await create(tester);
      await tester.tap(find.text('Copy sharing link'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump(const Duration(minutes: 11));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Copy sharing link'), findsNothing);
      expect(find.text('Share'), findsNothing);
      await dispose(tester);
    },
  );

  for (final locale in ['en', 'pl']) {
    testWidgets(
      'centered ready state fits 320px and keeps copy stable: $locale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(
          tester,
          locale: locale,
          brightness: Brightness.dark,
          scale: 1.5,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(EntryShareCreationForm)),
        )!;
        await tester.tap(
          find.widgetWithText(PrimaryButton, l10n.sharingCreate),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.sharingCreated), findsOneWidget);
        final notice = find.text(
          l10n.sharingLinkOnceNotice,
          findRichText: true,
        );
        expect(notice, findsOneWidget);
        final richText = tester.widget<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.textSpan?.toPlainText() == l10n.sharingLinkOnceNotice,
          ),
        );
        expect(
          (richText.textSpan as TextSpan).children!
              .whereType<TextSpan>()
              .singleWhere((span) => span.text == l10n.sharingLinkOnceEmphasis)
              .style!
              .fontWeight,
          FontWeight.w700,
        );
        expect(find.byType(EntryShareActionFooter), findsNothing);
        final button = find.widgetWithText(PrimaryButton, l10n.sharingCopyLink);
        final before = tester.getRect(button);
        final share = tester.getRect(find.byType(AccentButton));
        final footer = tester.getRect(find.byType(AppActionFooter));
        expect(share.right, lessThan(before.left));
        expect(share.top, closeTo(before.top, 0.1));
        expect(share.height, closeTo(before.height, 0.1));
        expect(share.width, closeTo(before.width, 0.1));
        expect(footer.left, 0);
        expect(footer.right, 320);
        expect(footer.bottom, 740);
        expect(before.bottom, greaterThan(680));
        expect(before.bottom, lessThan(740));
        expect(tester.getCenter(find.text(l10n.sharingCreated)).dx, 160);
        final contentAlignment = find
            .ancestor(
              of: find.text(l10n.sharingCreated),
              matching: find.byType(Align),
            )
            .first;
        expect(
          tester.widget<Align>(contentAlignment).alignment,
          const Alignment(0, -0.15),
        );
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(tester.getRect(button), before);
        expect(find.byIcon(Icons.check_circle_outline), findsNothing);
        final titleBefore = tester.getRect(find.text(l10n.sharingCreated));
        final noticeBefore = tester.getRect(notice);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.getRect(button), before);
        expect(find.text(l10n.sharingCopiedLink), findsOneWidget);
        expect(tester.getRect(find.text(l10n.sharingCreated)), titleBefore);
        expect(tester.getRect(notice), noticeBefore);
        expect(tester.takeException(), isNull);
        await capture(tester, 'ready-$locale-dark-320-150');
        await dispose(tester);
        await tester.pump(const Duration(seconds: 46));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'system Share sends only the link, supports cancellation and guards lock',
    (tester) async {
      await pump(tester);
      await create(tester);
      expect(nativeShares, isEmpty);
      expect(find.widgetWithText(PrimaryButton, 'Share'), findsNothing);
      expect(find.widgetWithText(AccentButton, 'Share'), findsOneWidget);
      final shareButton = find.widgetWithText(OutlinedButton, 'Share');
      expect(shareButton, findsOneWidget);
      final style = tester.widget<OutlinedButton>(shareButton).style!;
      final foreground = AppColors.onSurface(
        Theme.of(tester.element(shareButton)).brightness,
      );
      expect(style.foregroundColor!.resolve({}), foreground);
      expect(style.side!.resolve({})!.color, foreground);
      expect(style.backgroundColor, isNull);
      expect(find.byIcon(Icons.ios_share), findsNothing);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(nativeShares, hasLength(1));
      expect(
        nativeShares.single['text'],
        startsWith('https://stage.palladin.io/share/$_shareId#v=1&key='),
      );
      expect(
        nativeShares.single['text'],
        isNot(contains('synthetic-password')),
      );
      expect(nativeShares.single['subject'], isNull);
      expect(nativeShares.single['originWidth'], greaterThan(0));
      expect(clipboard, isNull);
      expect(requests, hasLength(1));
      expect(find.text('Your link is ready'), findsOneWidget);
      authEvents.add(unlocked.copyWith(clearKeys: true, isVaultLocked: true));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsNothing);
      expect(nativeShares, hasLength(1));
      await dispose(tester);
    },
  );

  testWidgets(
    'late native Share failure cannot revive a backgrounded capability',
    (tester) async {
      await pump(tester);
      await create(tester);
      final pending = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            (_) => pending.future,
          );
      await tester.tap(find.text('Share'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      pending.completeError(PlatformException(code: 'synthetic'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsNothing);
      expect(find.text('Copy sharing link'), findsNothing);
      expect(find.textContaining('Could not open sharing'), findsNothing);
      expect(clipboard, isNull);
      expect(requests, hasLength(1));
      await dispose(tester);
    },
  );

  testWidgets(
    'optional PIN exposes warning, validates and combines with email OTP',
    (tester) async {
      await pump(tester);
      await ready(tester);
      await section(tester, 'Security');
      await visible(tester, find.text('No additional secret'));
      await tester.tap(find.text('No additional secret'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PIN').last);
      await tester.pumpAndSettle();
      expect(find.byType(EntryShareCreationForm), findsOneWidget);
      await enter(tester, 'PIN', '12345');
      await create(tester);
      await visible(tester, input('PIN'));
      expect(
        tester.widget<OnboardingTextField>(input('PIN')).feedbackVisible,
        isTrue,
      );
      expect(requests, isEmpty);
      expect(find.textContaining('A PIN is weaker'), findsOneWidget);
      await enter(tester, 'PIN', '739284');
      await create(tester);
      expect(requests, isEmpty);
      await enter(tester, 'Confirm password or PIN', '739284');
      await create(tester);
      expect(requests.single.options.protectionSecret, '739284');
      expect(
        requests.single.options.recipientMode,
        EntryShareRecipientMode.namedRecipient,
      );
      await dispose(tester);
    },
  );

  testWidgets(
    'ambiguous create preserves one request and removes editable secrets',
    (tester) async {
      when(
        () => remote.create(
          any(),
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        requests.add(
          invocation.positionalArguments[2] as EntryShareCreationRequest,
        );
        if (requests.length == 1) throw const EntrySharingRequestException();
      });
      await pump(tester);
      await ready(tester);
      await create(tester);
      expect(find.byType(EntryShareCreationForm), findsNothing);
      expect(find.textContaining('The result is uncertain'), findsOneWidget);
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.last, same(requests.first));
      expect(find.text('Your link is ready'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets('lock removes source and draft controllers without a POST', (
    tester,
  ) async {
    await pump(tester);
    await ready(tester);
    final controller = tester
        .widget<OnboardingTextField>(
          input('Recipient emails (comma-separated)'),
        )
        .controller;
    authEvents.add(unlocked.copyWith(clearKeys: true, isVaultLocked: true));
    await tester.pumpAndSettle();
    expect(find.byType(EntryShareCreationForm), findsNothing);
    expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
    expect(controller.text, isEmpty);
    expect(requests, isEmpty);
    await dispose(tester);
  });

  testWidgets(
    'background invalidates a created capability and resume cannot copy it',
    (tester) async {
      await pump(tester);
      await ready(tester);
      await create(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Copy sharing link'), findsNothing);
      expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
      expect(clipboard, isNull);
      await dispose(tester);
    },
  );

  testWidgets(
    'memory-key replacement clears form through foreground authority repair',
    (tester) async {
      await pump(tester);
      getIt<VaultSessionStore>().setMemberPrivateKey(Uint8List(32));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(EntryShareCreationForm), findsNothing);
      expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'lock wipes a pending reader key immediately and rejects late plaintext',
    (tester) async {
      final pending = Completer<CanonicalEntrySnapshot>();
      final source = _source();
      when(
        () => local.reveal(
          expected: any(named: 'expected'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((invocation) {
        copiedKeys.add(
          invocation.namedArguments[#memberPrivateKey] as Uint8List,
        );
        return pending.future;
      });
      // The source remains pending, so no pumpAndSettle while its skeleton animates.
      getIt.registerSingleton<EnvConfig>(
        EnvConfig.staging(
          apiBaseUrl: 'https://stage.example.test',
          sharingWebOrigin: 'https://stage.palladin.io',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<AuthBloc>.value(
            value: auth,
            child: EntryShareCreationPage(entry: _entry),
          ),
        ),
      );
      await tester.pump();
      expect(copiedKeys.single, everyElement(9));
      authEvents.add(unlocked.copyWith(clearKeys: true, isVaultLocked: true));
      await tester.pumpAndSettle();
      expect(copiedKeys.single, everyElement(0));
      pending.complete(source);
      await tester.pumpAndSettle();
      expect(source.payload, isEmpty);
      expect(find.byType(EntryShareCreationForm), findsNothing);
      await dispose(tester);
    },
  );

  testWidgets('missing origin fails before source reveal or creation', (
    tester,
  ) async {
    await pump(tester, origin: '');
    expect(find.textContaining('Sharing is not configured'), findsOneWidget);
    expect(copiedKeys, isEmpty);
    expect(requests, isEmpty);
    await dispose(tester);
  });

  testWidgets(
    'Polish dark large-text form fits 320px and footer stays visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester, locale: 'pl', brightness: Brightness.dark, scale: 1.5);
      await capture(tester, 'create-pl-dark-320-150-fields');
      expect(tester.takeException(), isNull);
      await section(tester, 'Zabezpieczenie');
      await visible(tester, find.text('Bez dodatkowego sekretu'));
      await tester.tap(find.text('Bez dodatkowego sekretu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PIN').last);
      await tester.pumpAndSettle();
      await enter(tester, 'PIN', '739284');
      await enter(tester, 'Potwierdź hasło lub PIN', '739284');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture(tester, 'create-pl-dark-320-150-pin');
      await chooseToggle(tester, 'Powiadom mnie o pierwszym odbiorze');
      await capture(tester, 'create-pl-dark-320-150-options');
      expect(tester.takeException(), isNull);
      final action = find.widgetWithText(PrimaryButton, 'Utwórz link');
      expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(740));
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Twój link jest gotowy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    },
  );
  testWidgets('English light mobile form and anyone warning remain usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    await capture(tester, 'create-en-light-390-fields');
    await ready(tester);
    await visible(tester, find.text('Only this person (email code)'));
    await tester.tap(find.text('Only this person (email code)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anyone with the link').last);
    await tester.pumpAndSettle();
    expect(find.byType(EntryShareCreationForm), findsOneWidget);
    expect(find.textContaining('The link can be forwarded'), findsOneWidget);
    await capture(tester, 'create-en-light-390-anyone');
    await create(tester);
    expect(
      requests.single.options.recipientMode,
      EntryShareRecipientMode.anyoneWithLink,
    );
    expect(requests.single.options.recipientEmail, isNull);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets(
    'covering the form with another page destroys the draft before returning',
    (tester) async {
      await pump(tester);
      await ready(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.byType(EntryShareCreationForm), findsNothing);
      expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
      expect(requests, isEmpty);
      await dispose(tester);
    },
  );
  testWidgets(
    'copy rechecks authority immediately, before the repair timer fires',
    (tester) async {
      await pump(tester);
      await ready(tester);
      await create(tester);
      getIt<VaultSessionStore>().setMemberPrivateKey(Uint8List(32));
      await tester.tap(find.text('Copy sharing link'));
      await tester.pumpAndSettle();
      expect(clipboard, isNull);
      expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'the real list CTA opens creation, suspends covered polling and refreshes on return',
    (tester) async {
      await pump(tester, fromList: true);
      verify(
        () => remote.list(
          _vaultId,
          _entryId,
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      verifyNever(
        () => remote.list(
          any(),
          any(),
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      );
      expect(find.byType(EntryShareCreationForm), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EntryShareCreationForm), findsNothing);
      verify(
        () => remote.list(
          _vaultId,
          _entryId,
          cursor: any(named: 'cursor'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      expect(find.text('No sharing links for this entry.'), findsOneWidget);
      await dispose(tester);
    },
  );
  testWidgets(
    'failed clipboard write rechecks session before publishing its error',
    (tester) async {
      await pump(tester);
      await ready(tester);
      await create(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              getIt<VaultSessionStore>().setMemberPrivateKey(Uint8List(32));
              throw PlatformException(code: 'clipboard-denied');
            }
            return null;
          });
      await tester.tap(find.text('Copy sharing link'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sharing is unavailable'), findsOneWidget);
      expect(find.text('Copy sharing link'), findsNothing);
      await dispose(tester);
    },
  );

  testWidgets(
    'the primary action stays above the keyboard on a narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester);
      await ready(tester);
      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final button = find.widgetWithText(PrimaryButton, 'Create sharing link');
      expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(440));
      expect(tester.takeException(), isNull);
      await create(tester);
      expect(requests, hasLength(1));
      await dispose(tester);
    },
  );
}
