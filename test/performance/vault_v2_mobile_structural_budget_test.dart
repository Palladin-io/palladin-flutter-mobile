import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_performance_budget.dart';

void main() {
  group('Vault v2 mobile structural release evidence', () {
    for (final entryCount in VaultPerformanceBudget.representativeEntryCounts) {
      test(
        '$entryCount-entry snapshot, delta, unlock, and search are bounded',
        () {
          final evidence = _Evidence.forVault(entryCount);

          expect(evidence.snapshotIndexItems, entryCount);
          expect(evidence.snapshotSecretItems, 0);
          expect(evidence.snapshotHistoryItems, 0);
          expect(
            evidence.snapshotPages,
            (entryCount / VaultPerformanceBudget.memberSyncPageItems).ceil(),
          );
          expect(
            evidence.deltaItems,
            VaultPerformanceBudget.onePercentDeltaItems(entryCount),
          );
          expect(evidence.localSearchCandidates, entryCount);
          expect(
            evidence.maximumConcurrentDecrypts,
            VaultPerformanceBudget.memberIndexDecryptConcurrency,
          );
          expect(
            evidence.maximumInFlightCiphertextBytes,
            lessThanOrEqualTo(_maximumInFlightIndexBytes),
            reason: evidence.structuralReport,
          );
        },
      );
    }

    test('grant and 100-version history stay on demand and page bounded', () {
      final evidence = _Evidence.forVault(
        VaultPerformanceBudget.maximumIndexedEntries,
      );

      expect(
        evidence.grantCanonicalSecrets,
        VaultPerformanceBudget.grantApprovalCanonicalSecrets,
      );
      expect(evidence.historyVersionsInInitialSync, 0);
      expect(
        evidence.historyPageItems,
        VaultPerformanceBudget.historyPageItems,
      );
      expect(
        evidence.maximumLoadedHistoryVersions,
        VaultPerformanceBudget.maximumLoadedHistoryVersions,
      );
      expect(
        evidence.historyPagesForMaximumLoad,
        VaultPerformanceBudget.maximumLoadedHistoryVersions ~/
            VaultPerformanceBudget.historyPageItems,
      );
    });

    test('envelope and page ceilings produce a logical byte budget', () {
      expect(
        VaultPerformanceBudget.memberSyncPageItems,
        lessThanOrEqualTo(VaultPerformanceBudget.maximumMemberSyncPageItems),
      );
      expect(_memberIndexCiphertextBytes, 32768);
      expect(_entryKeyCiphertextBytes, 48);
      expect(
        _maximumRequestedPageCiphertextBytes,
        VaultPerformanceBudget.memberSyncPageItems *
            (_memberIndexCiphertextBytes + _entryKeyCiphertextBytes),
      );
      expect(
        _maximumProtocolPageCiphertextBytes,
        VaultPerformanceBudget.maximumMemberSyncPageItems *
            (_memberIndexCiphertextBytes + _entryKeyCiphertextBytes),
      );
    });

    test('representative workloads contain structural values only', () {
      final report = _Evidence.forVault(1000).structuralReport;

      expect(report, isNot(contains('label')));
      expect(report, isNot(contains('query')));
      expect(report, isNot(contains('ciphertextContent')));
      expect(report, contains('entryCount=1000'));
      expect(report, contains('deltaItems=10'));
      expect(report, contains('logicalCiphertextBytes='));
    });
  });
}

final int _memberIndexCiphertextBytes =
    VaultProtocolEnvelopeService.maximumCiphertextBytes(
      VaultAadProfile.memberIndex,
    );
final int _entryKeyCiphertextBytes =
    VaultProtocolEnvelopeService.maximumCiphertextBytes(
      VaultAadProfile.entryKeyWrapper,
    );
final int _maximumInFlightIndexBytes =
    VaultPerformanceBudget.memberIndexDecryptConcurrency *
    (_memberIndexCiphertextBytes + _entryKeyCiphertextBytes);
final int _maximumRequestedPageCiphertextBytes =
    VaultPerformanceBudget.memberSyncPageItems *
    (_memberIndexCiphertextBytes + _entryKeyCiphertextBytes);
final int _maximumProtocolPageCiphertextBytes =
    VaultPerformanceBudget.maximumMemberSyncPageItems *
    (_memberIndexCiphertextBytes + _entryKeyCiphertextBytes);

final class _Evidence {
  const _Evidence({required this.entryCount});

  factory _Evidence.forVault(int entryCount) {
    if (!VaultPerformanceBudget.representativeEntryCounts.contains(
      entryCount,
    )) {
      throw ArgumentError.value(entryCount, 'entryCount');
    }
    return _Evidence(entryCount: entryCount);
  }

  final int entryCount;

  int get snapshotIndexItems => entryCount;
  int get snapshotSecretItems => 0;
  int get snapshotHistoryItems => 0;
  int get snapshotPages =>
      (entryCount / VaultPerformanceBudget.memberSyncPageItems).ceil();
  int get deltaItems => VaultPerformanceBudget.onePercentDeltaItems(entryCount);
  int get localSearchCandidates => entryCount;
  int get maximumConcurrentDecrypts =>
      VaultPerformanceBudget.memberIndexDecryptConcurrency;
  int get maximumInFlightCiphertextBytes => _maximumInFlightIndexBytes;
  int get grantCanonicalSecrets =>
      VaultPerformanceBudget.grantApprovalCanonicalSecrets;
  int get historyVersionsInInitialSync => 0;
  int get historyPageItems => VaultPerformanceBudget.historyPageItems;
  int get maximumLoadedHistoryVersions =>
      VaultPerformanceBudget.maximumLoadedHistoryVersions;
  int get historyPagesForMaximumLoad =>
      maximumLoadedHistoryVersions ~/ historyPageItems;

  String get structuralReport => <String>[
    'entryCount=$entryCount',
    'snapshotPages=$snapshotPages',
    'deltaItems=$deltaItems',
    'maximumConcurrentDecrypts=$maximumConcurrentDecrypts',
    'logicalCiphertextBytes=$maximumInFlightCiphertextBytes',
    'historyPageItems=$historyPageItems',
  ].join(',');
}
