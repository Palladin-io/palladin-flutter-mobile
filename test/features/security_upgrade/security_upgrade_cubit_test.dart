import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/security_upgrade/data/security_upgrade_remote_datasource.dart';
import 'package:mobile_palladin/features/security_upgrade/data/security_upgrade_service.dart';
import 'package:mobile_palladin/features/security_upgrade/domain/security_upgrade_start.dart';
import 'package:mobile_palladin/features/security_upgrade/presentation/cubit/security_upgrade_cubit.dart';
import 'package:mobile_palladin/features/unlock/data/models/account_response.dart';
import 'package:mocktail/mocktail.dart';

class _Service extends Mock implements SecurityUpgradeService {}

const _accountId = '00112233-4455-4677-8899-aabbccddeeff';
final _words = List.generate(24, (i) => 'word$i');

UpgradedAccountKeys _keys({bool fresh = true}) => UpgradedAccountKeys(
  accountId: _accountId,
  email: 'member@example.invalid',
  masterKey: Uint8List.fromList(List.filled(32, 1)),
  memberPrivateKey: Uint8List.fromList(List.filled(32, 2)),
  memberKeyVersion: 2,
  legacyPrivateKey: Uint8List.fromList(List.filled(32, 3)),
  legacyKeyVersion: 1,
  accountSecret: fresh ? Uint8List.fromList(List.filled(32, 4)) : null,
  recoveryMnemonic: fresh ? _words : null,
);

void main() {
  late _Service service;

  setUpAll(() {
    registerFallbackValue(_keys());
    registerFallbackValue(const AccountResponse(userId: _accountId));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    service = _Service();
    when(
      () => service.rewrapMemberEnvelopes(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((call) async {
      final onProgress =
          call.namedArguments[#onProgress] as void Function(RewrapProgress)?;
      onProgress?.call(const RewrapProgress(done: 0, total: 2));
      onProgress?.call(const RewrapProgress(done: 2, total: 2));
      return const KeyMigrationReport(
        memberEnvelopesPendingRewrap: 0,
        agentEnvelopesOnNonCurrentSuite: 1,
      );
    });
  });

  FreshSecurityUpgrade freshStart() => FreshSecurityUpgrade(
    password: 'password',
    account: const AccountResponse(userId: _accountId),
    legacyPrivateKey: Uint8List.fromList(List.filled(32, 3)),
  );

  void stubCommit(Future<UpgradedAccountKeys> Function() answer) => when(
    () => service.commit(
      migrationId: any(named: 'migrationId'),
      password: any(named: 'password'),
      account: any(named: 'account'),
      legacyPrivateKey: any(named: 'legacyPrivateKey'),
    ),
  ).thenAnswer((_) => answer());

  test(
    'fresh upgrade commits, re-wraps, then confirms the phrase and kit',
    () async {
      stubCommit(() async => _keys());
      final cubit = SecurityUpgradeCubit(
        service: service,
        start: freshStart(),
        random: Random(1),
      );
      addTearDown(cubit.close);

      await cubit.run();
      expect(cubit.state, isA<SecurityUpgradeRecoveryPhrase>());

      cubit.acknowledgePhrase();
      final confirm = cubit.state as SecurityUpgradeConfirmPhrase;
      expect(confirm.positions, hasLength(3));

      cubit.confirmPhrase(['wrong', 'wrong', 'wrong']);
      expect((cubit.state as SecurityUpgradeConfirmPhrase).mismatch, isTrue);

      cubit.confirmPhrase([
        for (final position in confirm.positions) _words[position - 1],
      ]);
      expect(cubit.state, isA<SecurityUpgradeEmergencyKit>());
      expect(cubit.emergencyKitSecret, Uint8List.fromList(List.filled(32, 4)));

      cubit.acknowledgeEmergencyKit();
      final done = cubit.state as SecurityUpgradeDone;
      expect(done.privateKey, Uint8List.fromList(List.filled(32, 2)));
      expect(cubit.emergencyKitSecret, isNull);
    },
  );

  test(
    'a network error stops at the step and retry reuses the migration id',
    () async {
      final ids = <String>[];
      var attempts = 0;
      when(
        () => service.commit(
          migrationId: any(named: 'migrationId'),
          password: any(named: 'password'),
          account: any(named: 'account'),
          legacyPrivateKey: any(named: 'legacyPrivateKey'),
        ),
      ).thenAnswer((call) async {
        ids.add(call.namedArguments[#migrationId] as String);
        if (attempts++ == 0) {
          throw const SecurityUpgradeException(
            SecurityUpgradeErrorKind.network,
          );
        }
        return _keys();
      });
      final cubit = SecurityUpgradeCubit(service: service, start: freshStart());
      addTearDown(cubit.close);

      await cubit.run();
      final stopped = cubit.state as SecurityUpgradeProgress;
      expect(stopped.error, SecurityUpgradeErrorKind.network);
      expect(stopped.accountKey, UpgradeStepStatus.failed);

      await cubit.retry();
      expect(cubit.state, isA<SecurityUpgradeRecoveryPhrase>());
      expect(ids.toSet(), hasLength(1));
    },
  );

  test('a failed re-wrap resumes without committing again', () async {
    stubCommit(() async => _keys());
    var rewraps = 0;
    when(
      () => service.rewrapMemberEnvelopes(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async {
      if (rewraps++ == 0) {
        throw const SecurityUpgradeException(SecurityUpgradeErrorKind.network);
      }
      return const KeyMigrationReport(
        memberEnvelopesPendingRewrap: 0,
        agentEnvelopesOnNonCurrentSuite: 0,
      );
    });
    final cubit = SecurityUpgradeCubit(service: service, start: freshStart());
    addTearDown(cubit.close);

    await cubit.run();
    expect(
      (cubit.state as SecurityUpgradeProgress).vaults,
      UpgradeStepStatus.failed,
    );
    await cubit.retry();

    expect(cubit.state, isA<SecurityUpgradeRecoveryPhrase>());
    verify(
      () => service.commit(
        migrationId: any(named: 'migrationId'),
        password: any(named: 'password'),
        account: any(named: 'account'),
        legacyPrivateKey: any(named: 'legacyPrivateKey'),
      ),
    ).called(1);
  });

  test('a resumed upgrade only re-wraps and finishes', () async {
    final cubit = SecurityUpgradeCubit(
      service: service,
      start: ResumedSecurityUpgrade(_keys(fresh: false)),
    );
    addTearDown(cubit.close);

    await cubit.run();

    expect(cubit.state, isA<SecurityUpgradeDone>());
    verifyNever(
      () => service.commit(
        migrationId: any(named: 'migrationId'),
        password: any(named: 'password'),
        account: any(named: 'account'),
        legacyPrivateKey: any(named: 'legacyPrivateKey'),
      ),
    );
  });
}
