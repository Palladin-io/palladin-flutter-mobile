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
);

void main() {
  late _Service service;
  late List<String> calls;

  setUpAll(() {
    registerFallbackValue(_keys());
    registerFallbackValue(const AccountResponse(userId: _accountId));
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    service = _Service();
    calls = [];
    when(
      () => service.rewrapMemberEnvelopes(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((call) async {
      calls.add('rewrap');
      final onProgress =
          call.namedArguments[#onProgress] as void Function(RewrapProgress)?;
      onProgress?.call(const RewrapProgress(done: 0, total: 2));
      onProgress?.call(const RewrapProgress(done: 2, total: 2));
    });
    when(
      () => service.migrateAgentMessageKeys(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async {
      calls.add('messageKeys');
      return 1;
    });
    when(() => service.cleanUp(any())).thenAnswer((_) async {
      calls.add('cleanUp');
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

  void stubCommit(Future<UpgradedAccountKeys> Function() answer) =>
      when(
        () => service.commit(
          migrationId: any(named: 'migrationId'),
          password: any(named: 'password'),
          account: any(named: 'account'),
          legacyPrivateKey: any(named: 'legacyPrivateKey'),
          recoveryMnemonic: any(named: 'recoveryMnemonic'),
        ),
      ).thenAnswer((_) {
        calls.add('commit');
        return answer();
      });

  SecurityUpgradeCubit freshCubit() => SecurityUpgradeCubit(
    service: service,
    start: freshStart(),
    random: Random(1),
    generatePhrase: () => _words,
  );

  Future<void> confirm(SecurityUpgradeCubit cubit) async {
    cubit.acknowledgePhrase();
    final positions = (cubit.state as SecurityUpgradeConfirmPhrase).positions;
    await cubit.confirmPhrase([
      for (final position in positions) _words[position - 1],
    ]);
  }

  test(
    'the phrase is confirmed before the commit, the kit comes last',
    () async {
      stubCommit(() async => _keys());
      final cubit = freshCubit();
      addTearDown(cubit.close);

      await cubit.start();
      expect(cubit.state, isA<SecurityUpgradeRecoveryPhrase>());
      cubit.acknowledgePhrase();
      await cubit.confirmPhrase(['wrong', 'wrong', 'wrong']);
      expect((cubit.state as SecurityUpgradeConfirmPhrase).mismatch, isTrue);
      expect(
        calls,
        isEmpty,
        reason: 'nothing is committed before confirmation',
      );

      final positions = (cubit.state as SecurityUpgradeConfirmPhrase).positions;
      await cubit.confirmPhrase([
        for (final position in positions) _words[position - 1],
      ]);

      expect(calls, ['commit', 'rewrap', 'messageKeys', 'cleanUp']);
      verify(
        () => service.commit(
          migrationId: any(named: 'migrationId'),
          password: any(named: 'password'),
          account: any(named: 'account'),
          legacyPrivateKey: any(named: 'legacyPrivateKey'),
          recoveryMnemonic: _words,
        ),
      ).called(1);
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
          recoveryMnemonic: any(named: 'recoveryMnemonic'),
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
      final cubit = freshCubit();
      addTearDown(cubit.close);

      await cubit.start();
      await confirm(cubit);
      final stopped = cubit.state as SecurityUpgradeProgress;
      expect(stopped.error, SecurityUpgradeErrorKind.network);
      expect(stopped.accountKey, UpgradeStepStatus.failed);

      await cubit.retry();
      expect(cubit.state, isA<SecurityUpgradeEmergencyKit>());
      expect(ids.toSet(), hasLength(1));
    },
  );

  test('a failed message-key step resumes without committing again', () async {
    stubCommit(() async => _keys());
    var attempts = 0;
    when(
      () => service.migrateAgentMessageKeys(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async {
      if (attempts++ == 0) {
        throw const SecurityUpgradeException(SecurityUpgradeErrorKind.network);
      }
      return 0;
    });
    final cubit = freshCubit();
    addTearDown(cubit.close);

    await cubit.start();
    await confirm(cubit);
    final stopped = cubit.state as SecurityUpgradeProgress;
    expect(stopped.agents, UpgradeStepStatus.failed);
    verifyNever(() => service.cleanUp(any()));

    await cubit.retry();
    expect(cubit.state, isA<SecurityUpgradeEmergencyKit>());
    expect(calls.where((call) => call == 'commit'), hasLength(1));
  });

  test('a resumed upgrade re-wraps, migrates and finishes', () async {
    final cubit = SecurityUpgradeCubit(
      service: service,
      start: ResumedSecurityUpgrade(_keys(fresh: false)),
    );
    addTearDown(cubit.close);

    await cubit.start();

    expect(cubit.state, isA<SecurityUpgradeDone>());
    expect(calls, ['rewrap', 'messageKeys', 'cleanUp']);
  });
}
