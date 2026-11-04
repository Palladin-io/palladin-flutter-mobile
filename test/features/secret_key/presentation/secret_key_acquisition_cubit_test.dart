import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/identity/device_pairing.dart';
import 'package:mobile_palladin/core/crypto/identity/secret_key_codec.dart';
import 'package:mobile_palladin/features/secret_key/data/datasources/secret_key_transfer_remote_datasource.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/device_transfer_sender_cubit.dart';
import 'package:mobile_palladin/features/secret_key/presentation/cubit/secret_key_acquisition_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/native_sodium.dart';

class _MockDatasource extends Mock
    implements SecretKeyTransferRemoteDatasource {}

const _accountId = '00112233-4455-6677-8899-aabbccddeeff';
const _transferId = '21212121-2121-2121-2121-212121212121';
final _challenge = Uint8List(32)..fillRange(0, 32, 0x22);
final _secret = Uint8List.fromList(List.generate(32, (i) => i + 1));

void main() {
  late DevicePairingCrypto crypto;
  late _MockDatasource datasource;

  setUpAll(() async {
    final sodium = await loadTestSodium();
    crypto = DevicePairingCrypto(sodiumLoader: () async => sodium);
  });

  setUp(() {
    datasource = _MockDatasource();
    when(
      () => datasource.cancelAsRecipient(
        transferId: any(named: 'transferId'),
        pollToken: any(named: 'pollToken'),
      ),
    ).thenAnswer((_) async {});
  });

  SecretKeyAcquisitionCubit build({DateTime Function()? now}) =>
      SecretKeyAcquisitionCubit(
        accountId: _accountId,
        datasource: datasource,
        crypto: crypto,
        pollInterval: Duration.zero,
        now: now,
      );

  /// What a signed-in sender does after verifying the offer.
  Future<PairingEnvelope> sealFor(
    Uint8List recipientKey,
    Uint8List challenge,
  ) => crypto.seal(
    confirmed: ConfirmedPairingOffer(
      PairingOffer.forRecipient(
        accountId: _accountId,
        transferId: _transferId,
        challenge: challenge,
        recipientPublicKey: recipientKey,
      ),
    ),
    recipientPublicKey: recipientKey,
    accountSecret: _secret,
  );

  void stubClaim(Future<ClaimedTransfer?> Function() answer) => when(
    () => datasource.claim(transferId: _transferId, pollToken: 'poll'),
  ).thenAnswer((_) => answer());

  Uint8List captureCreatedKey() => decodeTransferBytes(
    verify(() => datasource.createAsRecipient(captureAny())).captured.single
        as String,
  );

  group('showing this phone\'s code', () {
    setUp(() {
      when(() => datasource.createAsRecipient(any())).thenAnswer(
        (_) async => RecipientTransferSession(
          transferId: _transferId,
          challenge: encodeTransferBytes(_challenge),
          pollToken: 'poll',
        ),
      );
    });

    test('polls until approved and yields the Secret Key', () async {
      var polls = 0;
      late SecretKeyAcquisitionCubit cubit;
      stubClaim(() async {
        if (++polls < 3) return null;
        return ClaimedTransfer(
          accountId: _accountId.toUpperCase(),
          envelope: await sealFor(captureCreatedKey(), _challenge),
        );
      });
      cubit = build();
      final states = <SecretKeyAcquisitionState>[];
      final sub = cubit.stream.listen(states.add);
      await cubit.showCode();
      await sub.cancel();

      final shown = states.whereType<SecretKeyAcquisitionShowingCode>().single;
      expect(shown.qrPayload, startsWith('palladin-pair:v2:r:ISEhISEhISEhISEhISEhIQ.'));
      expect((cubit.state as SecretKeyAcquisitionAcquired).secret, _secret);
      expect(polls, 3);
      await cubit.close();
      verifyNever(
        () => datasource.cancelAsRecipient(
          transferId: any(named: 'transferId'),
          pollToken: any(named: 'pollToken'),
        ),
      );
    });

    test('rejects an envelope claimed for another account', () async {
      stubClaim(
        () async => ClaimedTransfer(
          accountId: 'fedcba98-7654-4321-8765-abcdefabcdef',
          envelope: await sealFor(captureCreatedKey(), _challenge),
        ),
      );
      final cubit = build();
      await cubit.showCode();
      expect(
        (cubit.state as SecretKeyAcquisitionFailed).failure,
        DeviceTransferFailure.accountMismatch,
      );
      await cubit.close();
    });

    test('an envelope bound to another challenge fails to open', () async {
      stubClaim(
        () async => ClaimedTransfer(
          accountId: _accountId,
          envelope: await sealFor(
            captureCreatedKey(),
            Uint8List(32)..fillRange(0, 32, 0x24),
          ),
        ),
      );
      final cubit = build();
      await cubit.showCode();
      expect(
        (cubit.state as SecretKeyAcquisitionFailed).failure,
        DeviceTransferFailure.decryptFailed,
      );
      await cubit.close();
    });

    test('stops at the session lifetime and cancels the session', () async {
      var clock = DateTime(2026, 11, 4);
      stubClaim(() async {
        clock = clock.add(const Duration(seconds: 200));
        return null;
      });
      final cubit = build(now: () => clock);
      await cubit.showCode();
      expect(
        (cubit.state as SecretKeyAcquisitionFailed).failure,
        DeviceTransferFailure.expired,
      );
      verify(
        () => datasource.cancelAsRecipient(
          transferId: _transferId,
          pollToken: 'poll',
        ),
      ).called(1);
      await cubit.close();
    });
  });

  test(
    'scanning a computer code attaches this phone and opens the envelope',
    () async {
      when(
        () => datasource.attachRecipient(
          transferId: _transferId,
          challenge: encodeTransferBytes(_challenge),
          recipientPublicKey: any(named: 'recipientPublicKey'),
        ),
      ).thenAnswer((_) async => 'poll');
      stubClaim(() async {
        final key = decodeTransferBytes(
          verify(
                () => datasource.attachRecipient(
                  transferId: _transferId,
                  challenge: any(named: 'challenge'),
                  recipientPublicKey: captureAny(named: 'recipientPublicKey'),
                ),
              ).captured.single
              as String,
        );
        return ClaimedTransfer(
          accountId: _accountId,
          envelope: await sealFor(key, _challenge),
        );
      });
      final cubit = build();
      await cubit.onScannedSenderCode(
        PairingQr.senderShows(_transferId, _challenge),
      );
      expect((cubit.state as SecretKeyAcquisitionAcquired).secret, _secret);
      await cubit.close();
    },
  );

  test('a device code is not a computer code', () async {
    final cubit = build();
    await cubit.onScannedSenderCode(
      'palladin-pair:v2:r:$_transferId.${encodeTransferBytes(_challenge)}',
    );
    expect(
      (cubit.state as SecretKeyAcquisitionFailed).failure,
      DeviceTransferFailure.invalidCode,
    );
    verifyZeroInteractions(datasource);
    await cubit.close();
  });

  group('Emergency Kit', () {
    final display = SecretKeyCodec.format(_accountId, _secret);

    test('accepts a typed Secret Key and wipes it on close', () async {
      final cubit = build();
      cubit.submitTypedSecretKey(display.toLowerCase());
      final acquired = cubit.state as SecretKeyAcquisitionAcquired;
      expect(acquired.secret, _secret);
      await cubit.close();
      expect(acquired.secret.every((byte) => byte == 0), isTrue);
    });

    blocTest<SecretKeyAcquisitionCubit, SecretKeyAcquisitionState>(
      'reports malformed and mistyped keys',
      build: build,
      act: (cubit) {
        cubit.submitTypedSecretKey('PSK2-123');
        cubit.submitTypedSecretKey(
          '${display.substring(0, display.length - 1)}0',
        );
      },
      expect: () => [
        isA<SecretKeyAcquisitionKitEntry>().having(
          (state) => state.error,
          'error',
          SecretKeyEntryError.malformed,
        ),
        isA<SecretKeyAcquisitionKitEntry>().having(
          (state) => state.error,
          'error',
          display.endsWith('0')
              ? SecretKeyEntryError.malformed
              : SecretKeyEntryError.checksumMismatch,
        ),
      ],
    );

    blocTest<SecretKeyAcquisitionCubit, SecretKeyAcquisitionState>(
      'accepts the kit QR only for this account',
      build: build,
      act: (cubit) {
        cubit.onScannedKitCode(
          SecretKeyCodec.emergencyKitQr(
            'fedcba98-7654-4321-8765-abcdefabcdef',
            _secret,
          ),
        );
        cubit.onScannedKitCode('https://example.com');
        cubit.onScannedKitCode(
          SecretKeyCodec.emergencyKitQr(_accountId, _secret),
        );
      },
      expect: () => [
        isA<SecretKeyAcquisitionKitEntry>().having(
          (state) => state.error,
          'error',
          SecretKeyEntryError.kitAccountMismatch,
        ),
        isA<SecretKeyAcquisitionKitEntry>().having(
          (state) => state.error,
          'error',
          SecretKeyEntryError.notKitCode,
        ),
        isA<SecretKeyAcquisitionAcquired>(),
      ],
    );
  });
}
