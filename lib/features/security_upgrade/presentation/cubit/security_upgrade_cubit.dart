import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../onboarding/domain/mnemonic.dart' as mnemonic;
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

/// Runs the resumable upgrade. A fresh upgrade first shows the new recovery
/// phrase and has it confirmed, then commits (the Secret Key is stored on the
/// device before the request), re-wraps member envelopes, migrates Vault
/// Agent message keys and shows the Emergency Kit. Network errors stop at the
/// current step and `retry` continues without repeating finished work.
class SecurityUpgradeCubit extends Cubit<SecurityUpgradeState> {
  SecurityUpgradeCubit({
    required this._service,
    required SecurityUpgradeStart start,
    Random? random,
    List<String> Function()? generatePhrase,
  }) : _start = start,
       _random = random ?? Random.secure(),
       super(const SecurityUpgradeProgress()) {
    _migrationId = _uuid();
    switch (start) {
      case ResumedSecurityUpgrade(:final keys):
        _keys = keys;
      case FreshSecurityUpgrade():
        _phrase = (generatePhrase ?? mnemonic.generateRecoveryMnemonic)();
    }
  }

  final SecurityUpgradeService _service;
  final SecurityUpgradeStart _start;
  final Random _random;
  late final String _migrationId;
  UpgradedAccountKeys? _keys;
  List<String>? _phrase;
  bool _phraseConfirmed = false;
  List<int> _positions = const [];

  /// Secret Key for the Emergency Kit step; owned by this cubit.
  Uint8List? get emergencyKitSecret => _keys?.accountSecret;

  SecurityUpgradeProgress get _progress => switch (state) {
    final SecurityUpgradeProgress progress => progress,
    _ => const SecurityUpgradeProgress(),
  };

  /// Entry point: a fresh upgrade starts at the recovery phrase, a resumed
  /// one goes straight to the re-wrap.
  Future<void> start() async {
    final phrase = _phrase;
    if (phrase != null && !_phraseConfirmed) {
      emit(SecurityUpgradeRecoveryPhrase(phrase));
      return;
    }
    await run();
  }

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
          recoveryMnemonic: _phrase!,
        );
        fresh.dispose();
      }
      if (isClosed) return;
      final keys = _keys!;
      emit(
        progress = progress.copyWith(
          accountKey: UpgradeStepStatus.done,
          vaults: UpgradeStepStatus.running,
        ),
      );
      await _service.rewrapMemberEnvelopes(
        keys,
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
      emit(
        progress = progress.copyWith(
          vaults: UpgradeStepStatus.done,
          agents: UpgradeStepStatus.running,
        ),
      );
      await _service.migrateAgentMessageKeys(keys.memberPrivateKey);
      if (isClosed) return;
      final report = await _service.cleanUp(keys);
      if (isClosed) return;
      keys.wipeLegacy();
      // Agent envelopes are re-wrapped after each agent rotates its own key;
      // they never block the member's upgrade.
      emit(
        progress = progress.copyWith(
          agents: report.agentEnvelopesOnNonCurrentSuite == 0
              ? UpgradeStepStatus.done
              : UpgradeStepStatus.waiting,
        ),
      );
      if (keys.accountSecret == null) {
        _finish();
      } else {
        emit(
          SecurityUpgradeEmergencyKit(
            email: keys.email,
            accountId: keys.accountId,
          ),
        );
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
          vaults: _keys != null && progress.vaults == UpgradeStepStatus.running
              ? UpgradeStepStatus.failed
              : null,
          agents: progress.agents == UpgradeStepStatus.running
              ? UpgradeStepStatus.failed
              : null,
        ),
      );
    }
  }

  Future<void> retry() => run();

  void acknowledgePhrase() {
    final words = _phrase;
    if (words == null) return;
    final positions = <int>{};
    while (positions.length < 3) {
      positions.add(_random.nextInt(words.length) + 1);
    }
    _positions = positions.toList()..sort();
    emit(SecurityUpgradeConfirmPhrase(positions: _positions));
  }

  void backToPhrase() {
    final words = _phrase;
    if (words != null) emit(SecurityUpgradeRecoveryPhrase(words));
  }

  /// [answers] are the words typed for [SecurityUpgradeConfirmPhrase.positions].
  /// A confirmed phrase starts the commit.
  Future<void> confirmPhrase(List<String> answers) async {
    final words = _phrase;
    if (words == null || answers.length != _positions.length) return;
    final matches = [
      for (var i = 0; i < _positions.length; i++)
        answers[i].trim().toLowerCase() == words[_positions[i] - 1],
    ].every((match) => match);
    if (!matches) {
      emit(SecurityUpgradeConfirmPhrase(positions: _positions, mismatch: true));
      return;
    }
    _phraseConfirmed = true;
    emit(const SecurityUpgradeProgress());
    await run();
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
