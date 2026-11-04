import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/identity/device_pairing.dart';
import 'package:mobile_palladin/core/storage/account_secret_store.dart';
import 'package:mobile_palladin/features/secret_key/data/datasources/secret_key_transfer_remote_datasource.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/device_transfer_sender_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/native_sodium.dart';

class _MockDatasource extends Mock
    implements SecretKeyTransferRemoteDatasource {}

class _MockStore extends Mock implements AccountSecretStore {}

const _accountId = '00112233-4455-6677-8899-aabbccddeeff';
const _transferId = '21212121-2121-2121-2121-212121212121';
final _challenge = Uint8List(32)..fillRange(0, 32, 0x22);

void main() {
  late DevicePairingCrypto crypto;
  late _MockDatasource datasource;
  late _MockStore store;
  late Uint8List recipientSeed;
  late Uint8List recipientKey;
  late Uint8List storedSecret;

  setUpAll(() async {
    final sodium = await loadTestSodium();
    crypto = DevicePairingCrypto(sodiumLoader: () async => sodium);
    registerFallbackValue(
      const PairingEnvelope(kemCiphertext: '', ciphertext: ''),
    );
  });

  setUp(() async {
    datasource = _MockDatasource();
    store = _MockStore();
    (recipientSeed, recipientKey) = await crypto.generateRecipientKey();
    storedSecret = Uint8List.fromList(List.generate(32, (i) => i + 1));
    when(() => store.read(_accountId)).thenAnswer((_) async => storedSecret);
    when(() => datasource.cancelAsSender(any())).thenAnswer((_) async {});
    when(
      () => datasource.submitEnvelope(any(), any()),
    ).thenAnswer((_) async {});
  });

  DeviceTransferSenderCubit build() => DeviceTransferSenderCubit(
    accountId: _accountId,
    datasource: datasource,
    crypto: crypto,
    secretStore: store,
  );

  void serve(Uint8List publicKey) =>
      when(() => datasource.readAsSender(_transferId)).thenAnswer(
        (_) async => SenderTransferState(
          challenge: encodeTransferBytes(_challenge),
          recipientPublicKey: encodeTransferBytes(publicKey),
        ),
      );

  test(
    'seals only after the SAS is confirmed and the recipient can open it',
    () async {
      serve(recipientKey);
      final cubit = build();
      await cubit.onScanned(
        PairingQr.recipientShows(_transferId, recipientKey),
      );

      final offer = PairingOffer.forRecipient(
        accountId: _accountId,
        transferId: _transferId,
        challenge: _challenge,
        recipientPublicKey: recipientKey,
      );
      expect(cubit.state, isA<DeviceTransferSenderCompare>());
      expect((cubit.state as DeviceTransferSenderCompare).sas, offer.sas);
      verifyNever(() => datasource.submitEnvelope(any(), any()));

      await cubit.approve();
      expect(cubit.state, isA<DeviceTransferSenderApproved>());
      final envelope =
          verify(
                () => datasource.submitEnvelope(_transferId, captureAny()),
              ).captured.single
              as PairingEnvelope;
      final opened = await crypto.open(
        offer: offer,
        envelope: envelope,
        recipientSeed: recipientSeed,
      );
      expect(opened, List.generate(32, (i) => i + 1));
      expect(storedSecret.every((byte) => byte == 0), isTrue);
      await cubit.close();
      verifyNever(() => datasource.cancelAsSender(any()));
    },
  );

  test(
    'a backend-substituted recipient key never reaches submitEnvelope',
    () async {
      final (_, substitute) = await crypto.generateRecipientKey();
      serve(substitute);
      final cubit = build();
      await cubit.onScanned(
        PairingQr.recipientShows(_transferId, recipientKey),
      );

      expect(
        (cubit.state as DeviceTransferSenderFailed).failure,
        DeviceTransferFailure.keyMismatch,
      );
      await cubit.approve();
      verifyNever(() => datasource.submitEnvelope(any(), any()));
      verify(() => datasource.cancelAsSender(_transferId)).called(1);
      verifyNever(() => store.read(any()));
    },
  );

  test('reject cancels the session without reading the Secret Key', () async {
    serve(recipientKey);
    final cubit = build();
    await cubit.onScanned(PairingQr.recipientShows(_transferId, recipientKey));
    await cubit.reject();

    expect(cubit.state, isA<DeviceTransferSenderRejected>());
    verify(() => datasource.cancelAsSender(_transferId)).called(1);
    verifyNever(() => store.read(any()));
  });

  test('a sender-shows code is not a device code', () async {
    final cubit = build();
    await cubit.onScanned(PairingQr.senderShows(_transferId, _challenge));
    expect(
      (cubit.state as DeviceTransferSenderFailed).failure,
      DeviceTransferFailure.invalidCode,
    );
    verifyNever(() => datasource.readAsSender(any()));
  });

  test('without a stored Secret Key nothing is sealed', () async {
    serve(recipientKey);
    when(() => store.read(_accountId)).thenAnswer((_) async => null);
    final cubit = build();
    await cubit.onScanned(PairingQr.recipientShows(_transferId, recipientKey));
    await cubit.approve();

    expect(
      (cubit.state as DeviceTransferSenderFailed).failure,
      DeviceTransferFailure.secretKeyMissing,
    );
    verifyNever(() => datasource.submitEnvelope(any(), any()));
    verify(() => datasource.cancelAsSender(_transferId)).called(1);
  });

  test('an expired session is reported as expired', () async {
    when(() => datasource.readAsSender(_transferId)).thenThrow(
      const SecretKeyTransferException(SecretKeyTransferErrorKind.expired),
    );
    final cubit = build();
    await cubit.onScanned(PairingQr.recipientShows(_transferId, recipientKey));
    expect(
      (cubit.state as DeviceTransferSenderFailed).failure,
      DeviceTransferFailure.expired,
    );
  });
}
