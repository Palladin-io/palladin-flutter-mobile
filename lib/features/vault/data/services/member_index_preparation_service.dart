import 'dart:async';
import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import 'member_entry_list_service.dart';

abstract interface class MemberVaultListLoader {
  Future<List<VaultEntity>> loadForMemberIndex(Uint8List memberPrivateKey);
}

/// Builds every unlocked MemberIndex once and shares concurrent consumers such
/// as Dashboard search and AutoFill without retaining the Member private key.
abstract interface class MemberIndexPreparer {
  Future<List<VaultEntity>> prepare(
    Uint8List memberPrivateKey, {
    bool ensureFresh = false,
  });

  void lock();
}

final class MemberIndexPreparationService implements MemberIndexPreparer {
  MemberIndexPreparationService({
    required MemberVaultListLoader vaults,
    required MemberEntryListLoader entries,
  }) : _vaults = vaults,
       _entries = entries;

  final MemberVaultListLoader _vaults;
  final MemberEntryListLoader _entries;
  Future<List<VaultEntity>>? _running;
  Completer<List<VaultEntity>>? _freshnessCompleter;
  Uint8List? _queuedPrivateKey;
  int _generation = 0;

  @override
  Future<List<VaultEntity>> prepare(
    Uint8List memberPrivateKey, {
    bool ensureFresh = false,
  }) {
    if (memberPrivateKey.length != 32) {
      return Future.error(
        const FormatException('Member private key must be 32 bytes'),
      );
    }
    final active = _running;
    if (active != null) {
      if (!ensureFresh) return active;
      final previousKey = _queuedPrivateKey;
      if (previousKey != null) {
        previousKey.fillRange(0, previousKey.length, 0);
      }
      _queuedPrivateKey = Uint8List.fromList(memberPrivateKey);
      return (_freshnessCompleter ??= Completer<List<VaultEntity>>()).future;
    }

    return _start(Uint8List.fromList(memberPrivateKey));
  }

  Future<List<VaultEntity>> _start(Uint8List keyCopy) {
    final generation = _generation;
    final core = (() async {
      final vaults = await _vaults.loadForMemberIndex(keyCopy);
      _requireCurrent(generation);
      for (final vault in vaults) {
        await _entries.load(vaultId: vault.id, memberPrivateKey: keyCopy);
        _requireCurrent(generation);
      }
      return List<VaultEntity>.unmodifiable(vaults);
    })();
    late final Future<List<VaultEntity>> operation;
    operation = core.whenComplete(() {
      keyCopy.fillRange(0, keyCopy.length, 0);
      if (!identical(_running, operation)) return;
      _running = null;
      final queuedKey = _queuedPrivateKey;
      final freshness = _freshnessCompleter;
      _queuedPrivateKey = null;
      _freshnessCompleter = null;
      if (queuedKey != null && freshness != null) {
        unawaited(_completeFreshPreparation(queuedKey, freshness));
      }
    });
    _running = operation;
    return operation;
  }

  Future<void> _completeFreshPreparation(
    Uint8List keyCopy,
    Completer<List<VaultEntity>> completer,
  ) async {
    try {
      completer.complete(await _start(keyCopy));
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  @override
  void lock() {
    _generation++;
    _running = null;
    final queuedKey = _queuedPrivateKey;
    _queuedPrivateKey = null;
    if (queuedKey != null) queuedKey.fillRange(0, queuedKey.length, 0);
    final freshness = _freshnessCompleter;
    _freshnessCompleter = null;
    if (freshness != null && !freshness.isCompleted) {
      freshness.completeError(const _MemberIndexPreparationInvalidated());
    }
    _entries.lock();
  }

  void _requireCurrent(int generation) {
    if (generation != _generation) {
      throw const _MemberIndexPreparationInvalidated();
    }
  }
}

final class _MemberIndexPreparationInvalidated implements Exception {
  const _MemberIndexPreparationInvalidated();
}
