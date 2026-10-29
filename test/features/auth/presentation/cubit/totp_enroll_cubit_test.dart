import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/auth/data/datasources/password_auth_remote_datasource.dart';
import 'package:mobile_palladin/features/auth/data/models/totp_enroll_model.dart';
import 'package:mobile_palladin/features/auth/data/services/password_auth_crypto_service.dart';
import 'package:mobile_palladin/features/auth/domain/password_auth_exceptions.dart';
import 'package:mobile_palladin/features/auth/presentation/cubit/totp_enroll_cubit.dart';
import 'package:mobile_palladin/features/unlock/data/datasources/account_remote_datasource.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mobile_palladin/features/unlock/data/services/identity_kdf_service.dart';

class _Account extends Mock implements AccountRemoteDatasource {}

class _Remote extends Mock implements PasswordAuthRemoteDatasource {}

class _Crypto extends Mock implements PasswordAuthCryptoService {}

const _userId = '00112233-4455-6677-8899-aabbccddeeff';
const _kdfSalt = 'AAECAwQFBgcICQoLDA0ODw';

void main() {
  late _Account account;
  late _Remote remote;
  late _Crypto crypto;
  late Uint8List credential;
  late TotpEnrollCubit cubit;

  setUpAll(() => registerFallbackValue(Uint8List(0)));

  setUp(() {
    account = _Account();
    remote = _Remote();
    crypto = _Crypto();
    credential = Uint8List.fromList(List.filled(32, 5));
    when(() => account.getAccount()).thenAnswer(
      (_) async => const AccountResponse(
        userId: _userId,
        kdf: IdentityKdfMetadata(
          securityVersion: 1,
          minimumSecurityVersion: 1,
          profileId: IdentityKdfProfile.id,
          kdfSalt: _kdfSalt,
          credentialRevision: 1,
          privateKeyWrapRevision: 1,
        ),
      ),
    );
    when(
      () => crypto.deriveCurrentAuthCredential(
        password: 'current-password',
        accountId: _userId,
        kdfSaltBase64: _kdfSalt,
      ),
    ).thenAnswer((_) async => credential);
    cubit = TotpEnrollCubit(
      datasource: remote,
      accountDatasource: account,
      cryptoService: crypto,
    );
  });

  tearDown(() => cubit.close());

  void stubEnroll() {
    when(() => remote.totpEnroll(any())).thenAnswer(
      (_) async => const TotpEnrollModel(
        secret: 'JBSWY3DPEHPK3PXP',
        otpauthUri: 'otpauth://totp/Palladin',
      ),
    );
  }

  test('starts by asking for the current password', () {
    expect(cubit.state, isA<TotpEnrollPasswordRequired>());
    verifyNever(() => remote.totpEnroll(any()));
  });

  test(
    'enroll and confirm prove the same derived credential, then wipe it',
    () async {
      stubEnroll();
      when(
        () => remote.totpConfirm('123456', any()),
      ).thenAnswer((_) async => ['recovery-1']);

      await cubit.enroll('current-password');
      expect(cubit.state, isA<TotpEnrollReady>());
      await cubit.confirm('123456');

      expect(cubit.state, isA<TotpEnrollConfirmed>());
      final sent = [
        verify(() => remote.totpEnroll(captureAny())).captured.single,
        verify(
          () => remote.totpConfirm('123456', captureAny()),
        ).captured.single,
      ];
      expect(sent.every((value) => identical(value, credential)), isTrue);
      expect(credential, everyElement(0));
    },
  );

  test(
    'wrong password returns to the prompt and wipes the credential',
    () async {
      when(
        () => remote.totpEnroll(any()),
      ).thenThrow(const TotpCurrentCredentialException());

      await cubit.enroll('current-password');

      expect(
        cubit.state,
        isA<TotpEnrollPasswordRequired>().having(
          (state) => state.error,
          'error',
          isA<TotpCurrentCredentialException>(),
        ),
      );
      expect(credential, everyElement(0));
    },
  );

  test('account without a password login is reported as unavailable', () async {
    when(
      () => remote.totpEnroll(any()),
    ).thenThrow(const TotpUnavailableException());

    await cubit.enroll('current-password');

    expect(cubit.state, isA<TotpEnrollUnavailable>());
    expect(credential, everyElement(0));
  });

  test('closing mid-enrollment wipes the retained credential', () async {
    stubEnroll();
    await cubit.enroll('current-password');

    await cubit.close();

    expect(credential, everyElement(0));
  });
}
