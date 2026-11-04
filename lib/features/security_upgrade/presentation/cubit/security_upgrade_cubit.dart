import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../data/security_upgrade_remote_datasource.dart';
import '../../data/security_upgrade_service.dart';
import '../../domain/security_upgrade_start.dart';

enum UpgradeStepStatus { waiting, running, done, failed }

/// States of the non-dismissable security upgrade screen.
sealed class SecurityUpgradeState {
  const SecurityUpgradeState();
}

final class SecurityUpgradeProgress extends SecurityUpgradeState {
  const SecurityUpgradeProgress({
    this.accountKey = UpgradeStepStatus.waiting,
    this.vaults = UpgradeStepStatus.waiting,
    this.vaultsDone = 0,
    this.vaultsTotal,
    this.agents = UpgradeStepStatus.waiting,
    this.error,
  });

  final UpgradeStepStatus accountKey;
  final UpgradeStepStatus vaults;
  final int vaultsDone;
  final int? vaultsTotal;
  final UpgradeStepStatus agents;

  /// Set when a step stopped; `retry` continues from that step.
  final SecurityUpgradeErrorKind? error;

  SecurityUpgradeProgress copyWith({
    UpgradeStepStatus? accountKey,
    UpgradeStepStatus? vaults,
    int? vaultsDone,
    int? vaultsTotal,
    UpgradeStepStatus? agents,
    SecurityUpgradeErrorKind? error,
    bool clearError = false,
  }) => SecurityUpgradeProgress(
    accountKey: accountKey ?? this.accountKey,
    vaults: vaults ?? this.vaults,
    vaultsDone: vaultsDone ?? this.vaultsDone,
    vaultsTotal: vaultsTotal ?? this.vaultsTotal,
    agents: agents ?? this.agents,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The user writes down the new recovery phrase.
final class SecurityUpgradeRecoveryPhrase extends SecurityUpgradeState {
  const SecurityUpgradeRecoveryPhrase(this.words);
  final List<String> words;
}

/// Three random positions (1-based) the user must re-enter.
final class SecurityUpgradeConfirmPhrase extends SecurityUpgradeState {
  const SecurityUpgradeConfirmPhrase({
    required this.positions,
    this.mismatch = false,
  });
  final List<int> positions;
  final bool mismatch;
}

final class SecurityUpgradeEmergencyKit extends SecurityUpgradeState {
  const SecurityUpgradeEmergencyKit({
    required this.email,
    required this.accountId,
  });
  final String email;
  final String accountId;
}

/// Upgrade finished; the page hands the keys to the session once.
final class SecurityUpgradeDone extends SecurityUpgradeState {
  const SecurityUpgradeDone({
    required this.masterKey,
    required this.privateKey,
  });
  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// Runs the resumable upgrade: commit, member re-wrap, recovery phrase,
/// Emergency Kit. Network errors stop at the current step and `retry`
/// continues without repeating finished work.
class SecurityUpgradeCubit extends Cubit<SecurityUpgradeState> {
  SecurityUpgradeCubit({
    required SecurityUpgradeService service,
    required SecurityUpgradeStart start,
    Random? random,
  }) : _service = service,
       _start = start,
       _random = random ?? Random.secure(),
       super(const SecurityUpgradeProgress()) {
    _migrationId = _uuid();
    if (start case ResumedSecurityUpgrade(:final keys)) _keys = keys;
  }

  final SecurityUpgradeService _service;
  final SecurityUpgradeStart _start;
  final Random _random;
  late final String _migrationId;
  UpgradedAccountKeys? _keys;
  List<int> _positions = const [];

  /// Secret Key for the Emergency Kit step; owned by this cubit.
  Uint8List? get emergencyKitSecret => _keys?.accountSecret;

  SecurityUpgradeProgress get _progress => switch (state) {
    final SecurityUpgradeProgress progress => progress,
    _ => const SecurityUpgradeProgress(),
  };

  Future<void> run() async {
    if (isClosed) return;
    var progress = _progress.copyWith(clearError: true);
    try {
      if (_keys == null) {
        final fresh = _start as FreshSecurityUpgrade;
        emit(
          progress = progress.copyWith(accountKey: UpgradeStepStatus.running),
        );
        _keys = await _service.commit(
          migrationId: _migrationId,
          password: fresh.password,
          account: fresh.account,
          legacyPrivateKey: fresh.legacyPrivateKey,
        );
        fresh.dispose();
      }
      if (isClosed) return;
      emit(
        progress = progress.copyWith(
          accountKey: UpgradeStepStatus.done,
          vaults: UpgradeStepStatus.running,
        ),
      );
      final report = await _service.rewrapMemberEnvelopes(
        _keys!,
        onProgress: (value) {
          if (isClosed) return;
          emit(
            progress = progress.copyWith(
              vaultsDone: value.done,
              vaultsTotal: value.total,
            ),
          );
        },
      );
      if (isClosed) return;
      _keys!.wipeLegacy();
      // Agent envelopes are re-wrapped after each agent rotates its own key;
      // they never block the member's upgrade.
      emit(
        progress = progress.copyWith(
          vaults: UpgradeStepStatus.done,
          agents: report.legacyAgentEnvelopes == 0
              ? UpgradeStepStatus.done
              : UpgradeStepStatus.waiting,
        ),
      );
      final words = _keys!.recoveryMnemonic;
      if (words == null) {
        _finish();
      } else {
        emit(SecurityUpgradeRecoveryPhrase(words));
      }
    } catch (error) {
      AppLogger.w(
        'SecurityUpgrade',
        'Upgrade step failed: ${error.runtimeType}',
      );
      if (isClosed) return;
      final kind = error is SecurityUpgradeException
          ? error.kind
          : SecurityUpgradeErrorKind.server;
      emit(
        progress.copyWith(
          error: kind,
          accountKey: _keys == null ? UpgradeStepStatus.failed : null,
          vaults: _keys == null ? null : UpgradeStepStatus.failed,
        ),
      );
    }
  }

  Future<void> retry() => run();

  void acknowledgePhrase() {
    final words = _keys?.recoveryMnemonic;
    if (words == null) return;
    final positions = <int>{};
    while (positions.length < 3) {
      positions.add(_random.nextInt(words.length) + 1);
    }
    _positions = positions.toList()..sort();
    emit(SecurityUpgradeConfirmPhrase(positions: _positions));
  }

  void backToPhrase() {
    final words = _keys?.recoveryMnemonic;
    if (words != null) emit(SecurityUpgradeRecoveryPhrase(words));
  }

  /// [answers] are the words typed for [SecurityUpgradeConfirmPhrase.positions].
  void confirmPhrase(List<String> answers) {
    final keys = _keys;
    final words = keys?.recoveryMnemonic;
    if (keys == null || words == null || answers.length != _positions.length) {
      return;
    }
    final matches = [
      for (var i = 0; i < _positions.length; i++)
        answers[i].trim().toLowerCase() == words[_positions[i] - 1],
    ].every((match) => match);
    if (!matches) {
      emit(SecurityUpgradeConfirmPhrase(positions: _positions, mismatch: true));
      return;
    }
    emit(
      SecurityUpgradeEmergencyKit(email: keys.email, accountId: keys.accountId),
    );
  }

  void acknowledgeEmergencyKit() => _finish();

  void _finish() {
    final keys = _keys;
    if (keys == null) return;
    emit(
      SecurityUpgradeDone(
        masterKey: Uint8List.fromList(keys.masterKey),
        privateKey: Uint8List.fromList(keys.memberPrivateKey),
      ),
    );
    keys.dispose();
    _keys = null;
  }

  @override
  Future<void> close() {
    _keys?.dispose();
    _keys = null;
    _start.dispose();
    return super.close();
  }

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
