import 'dart:typed_data';

import '../../domain/entities/vault_entity.dart';
import 'member_entry_list_service.dart';

abstract interface class MemberVaultListLoader {
  Future<List<VaultEntity>> loadForMemberIndex(Uint8List memberPrivateKey);
}

/// Builds every unlocked MemberIndex once and shares concurrent consumers such
/// as Dashboard search and AutoFill without retaining the Member private key.
abstract interface class MemberIndexPreparer {
  Future<List<VaultEntity>> prepare(Uint8List memberPrivateKey);

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
  int _generation = 0;

  @override
  Future<List<VaultEntity>> prepare(Uint8List memberPrivateKey) {
    if (memberPrivateKey.length != 32) {
      return Future.error(
        const FormatException('Member private key must be 32 bytes'),
      );
    }
    final active = _running;
    if (active != null) return active;

    final generation = _generation;
    final keyCopy = Uint8List.fromList(memberPrivateKey);
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
      if (identical(_running, operation)) _running = null;
    });
    _running = operation;
    return operation;
  }

  @override
  void lock() {
    _generation++;
    _running = null;
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
