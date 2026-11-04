import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_palladin/core/crypto/identity/device_pairing.dart';
import 'package:mobile_palladin/core/crypto/identity/secret_key_codec.dart';
import 'package:mobile_palladin/core/storage/account_secret_store.dart';
import 'package:mobile_palladin/features/secret_key/data/datasources/secret_key_transfer_remote_datasource.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/device_transfer_sender_cubit.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/secret_key_acquisition_cubit.dart';
import 'package:mobile_palladin/features/secret_key/presentation/pages/device_transfer_approve_page.dart';
import 'package:mobile_palladin/features/secret_key/presentation/pages/secret_key_acquisition_page.dart';
import 'package:mobile_palladin/features/shell/presentation/pages/app_shell.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/native_sodium.dart';

class _MockDatasource extends Mock
    implements SecretKeyTransferRemoteDatasource {}

class _MockStore extends Mock implements AccountSecretStore {}

const _accountId = '00112233-4455-6677-8899-aabbccddeeff';
final _transferId = encodeTransferBytes(List.filled(16, 0x21));
final _challenge = Uint8List(32)..fillRange(0, 32, 0x22);
final _secret = Uint8List.fromList(List.generate(32, (i) => i + 1));

Widget _app({required Widget home, GoRouter? router}) {
  Widget scope(BuildContext context, Widget? child) => AppShellScope(
    openSettingsDrawer: () {},
    setBottomNavHidden: (_) {},
    setFab: (_, _) {},
    clearFab: (_) {},
    child: child!,
  );
  return router == null
      ? MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: scope,
          home: home,
        )
      : MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: scope,
          routerConfig: router,
        );
}

void main() {
  late DevicePairingCrypto crypto;
  late _MockDatasource datasource;

  setUpAll(() async {
    final sodium = await loadTestSodium();
    crypto = DevicePairingCrypto(sodiumLoader: () async => sodium);
    registerFallbackValue(
      const PairingEnvelope(kemCiphertext: '', ciphertext: ''),
    );
  });

  setUp(() {
    datasource = _MockDatasource();
    when(() => datasource.cancelAsSender(any())).thenAnswer((_) async {});
    when(
      () => datasource.submitEnvelope(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => datasource.cancelAsRecipient(
        transferId: any(named: 'transferId'),
        pollToken: any(named: 'pollToken'),
      ),
    ).thenAnswer((_) async {});
  });

  group('DeviceTransferApproveView', () {
    late _MockStore store;
    late Uint8List recipientKey;

    setUp(() async {
      store = _MockStore();
      when(
        () => store.read(_accountId),
      ).thenAnswer((_) async => Uint8List.fromList(_secret));
      (_, recipientKey) = await crypto.generateRecipientKey();
      when(() => datasource.readAsSender(_transferId)).thenAnswer(
        (_) async => SenderTransferState(
          challenge: encodeTransferBytes(_challenge),
          recipientPublicKey: encodeTransferBytes(recipientKey),
        ),
      );
    });

    Future<DeviceTransferSenderCubit> pump(WidgetTester tester) async {
      final cubit = DeviceTransferSenderCubit(
        accountId: _accountId,
        datasource: datasource,
        crypto: crypto,
        secretStore: store,
      );
      await tester.pumpWidget(
        _app(
          home: BlocProvider.value(
            value: cubit,
            child: DeviceTransferApproveView(
              scanQr: (_, {required title, required instruction}) async =>
                  PairingQr.recipientShows(_transferId, recipientKey),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('scans, shows the SAS and approves', (tester) async {
      final cubit = await pump(tester);
      expect(find.text('Secret Key saved in secure storage'), findsOneWidget);

      await tester.tap(find.text('Add a device'));
      await tester.runAsync(() async {
        while (cubit.state is! DeviceTransferSenderCompare) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      final sas = PairingOffer.forRecipient(
        accountId: _accountId,
        transferId: _transferId,
        challenge: _challenge,
        recipientPublicKey: recipientKey,
      ).sas;
      expect(find.text(sas), findsOneWidget);
      verifyNever(() => datasource.submitEnvelope(any(), any()));

      await tester.tap(find.text('Approve'));
      await tester.runAsync(() async {
        while (cubit.state is! DeviceTransferSenderApproved) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Device approved'), findsOneWidget);
      verify(() => datasource.submitEnvelope(_transferId, any())).called(1);
    });

    testWidgets('reject sends nothing', (tester) async {
      final cubit = await pump(tester);
      await tester.tap(find.text('Add a device'));
      await tester.runAsync(() async {
        while (cubit.state is! DeviceTransferSenderCompare) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      expect(find.text('Request rejected'), findsOneWidget);
      verifyNever(() => datasource.submitEnvelope(any(), any()));
    });
  });

  group('SecretKeyAcquisitionView', () {
    late SecretKeyAcquisitionCubit cubit;
    Uint8List? result;

    Future<void> pump(WidgetTester tester) async {
      result = null;
      cubit = SecretKeyAcquisitionCubit(
        accountId: _accountId,
        datasource: datasource,
        crypto: crypto,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await context.push<Uint8List>('/acquire'),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/acquire',
            builder: (_, _) => BlocProvider.value(
              value: cubit,
              child: SecretKeyAcquisitionView(
                scanQr: (_, {required title, required instruction}) async =>
                    SecretKeyCodec.emergencyKitQr(_accountId, _secret),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(_app(home: const SizedBox(), router: router));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('typed Secret Key pops a copy of the key', (tester) async {
      await pump(tester);
      expect(find.text('Set up this phone'), findsOneWidget);
      await tester.tap(find.text('Use Emergency Kit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'PSK2-123');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This doesn't look like a Secret Key. Check the characters and try again.",
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField),
        SecretKeyCodec.format(_accountId, _secret),
      );
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(result, _secret);
      await cubit.close();
      expect(result, _secret, reason: 'the popped copy survives cubit close');
    });

    testWidgets('scanning the kit QR pops the key', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Use Emergency Kit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan kit QR code'));
      await tester.pumpAndSettle();
      expect(result, _secret);
      await cubit.close();
    });

    testWidgets('showing a code renders the QR and SAS and can be cancelled', (
      tester,
    ) async {
      when(() => datasource.createAsRecipient(any())).thenAnswer(
        (_) async => RecipientTransferSession(
          transferId: _transferId,
          challenge: encodeTransferBytes(_challenge),
          pollToken: 'poll',
        ),
      );
      when(
        () => datasource.claim(transferId: _transferId, pollToken: 'poll'),
      ).thenAnswer((_) async => null);
      await pump(tester);
      await tester.tap(find.text('Show a code to another phone'));
      await tester.runAsync(() async {
        while (cubit.state is! SecretKeyAcquisitionShowingCode) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('transfer-qr')), findsOneWidget);
      expect(
        find.text((cubit.state as SecretKeyAcquisitionShowingCode).sas),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Set up this phone'), findsOneWidget);
      verify(
        () => datasource.cancelAsRecipient(
          transferId: _transferId,
          pollToken: 'poll',
        ),
      ).called(1);
      await cubit.close();
    });
  });
}
