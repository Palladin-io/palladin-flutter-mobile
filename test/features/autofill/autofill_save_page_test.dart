import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_save_controller.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_save_page.dart';
import 'package:mobile_palladin/features/vault/data/services/key_entry_creation_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _VaultRemote extends Mock implements VaultRemoteDatasource {}

class _VaultCrypto extends Mock implements VaultCryptoService {}

class _EntryCrypto extends Mock implements EntryV2CryptoService {}

class _Auth extends Mock implements AuthBloc {}

class _Vaults extends Mock implements VaultListCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('save-page-test');
  late AutoFillSaveController controller;
  late _Auth auth;
  late _Vaults vaults;
  late int createAttempts;
  setUp(() async {
    await getIt.reset();
    createAttempts = 0;
    getIt.registerFactory<KeyEntryCreationService>(() {
      createAttempts++;
      return KeyEntryCreationService(
        sessions: VaultSessionStore()..setMemberPrivateKey(Uint8List(32)),
        entries: _Entries(),
        vaults: _VaultRemote(),
        vaultCrypto: _VaultCrypto(),
        entryCrypto: _EntryCrypto(),
        autoFillMutationNotifier: AutoFillMutationNotifier(),
      );
    });
    auth = _Auth();
    when(() => auth.state).thenReturn(
      AuthAuthenticated(
        userId: 'account',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
      ),
    );
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    vaults = _Vaults();
    final vault = VaultEntity(
      id: 'vault',
      name: 'Synthetic Vault',
      grantMode: GrantMode.granular,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      entryCount: 0,
      activeGrantCount: 0,
      memberCount: 1,
    );
    when(() => vaults.state).thenReturn(VaultListLoaded([vault]));
    when(() => vaults.stream).thenAnswer((_) => const Stream.empty());
    when(() => vaults.loadIfNeeded(any())).thenAnswer((_) async {});
    getIt.registerSingleton<VaultListCubit>(vaults);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'activate' => 'session',
            'pending' => 'request',
            'validate' => true,
            'take' => {
              'id': 'request',
              'packageName': 'synthetic.package',
              'mode': 'WEB',
              'domains': ['login.example.com'],
              'username': 'synthetic-user',
              'password': 'synthetic-password',
              'remainingMs': 120000,
            },
            _ => null,
          },
        );
    controller = AutoFillSaveController(channel: channel);
    await controller.synchronize('account', unlocked: true);
  });
  tearDown(() async {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await getIt.reset();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AutoFillSavePage(
            controller: controller,
            draft: controller.draft!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'source display and Vault selection never create before explicit Save',
    (tester) async {
      await show(tester);
      expect(find.text('https://login.example.com'), findsOneWidget);
      expect(createAttempts, 0);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.globalEntriesChooseVault));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic Vault'));
      await tester.pumpAndSettle();
      expect(createAttempts, 0);
      await tester.tap(find.text(l10n.entrySaveAction));
      await tester.pumpAndSettle();
      expect(createAttempts, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
