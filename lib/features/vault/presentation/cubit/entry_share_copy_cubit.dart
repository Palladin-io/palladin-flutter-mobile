import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/entry_sharing/entry_share_copy_service.dart';
import '../../data/services/entry_sharing/entry_share_lifetime.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_copy.dart';
import '../../domain/entities/entry_share_list.dart';

enum EntryShareCopyPhase {
  editing,
  creatingVault,
  preparing,
  saving,
  retry,
  saved,
  unavailable,
}

final class EntryShareCopyState {
  const EntryShareCopyState({
    this.phase = EntryShareCopyPhase.editing,
    this.inputError,
    this.failed = false,
    this.vaultCreationFailed = false,
    this.vaultId,
    this.entryId,
  });
  final EntryShareCopyPhase phase;
  final EntryShareCopyInputError? inputError;
  final bool failed;
  final bool vaultCreationFailed;
  final String? vaultId, entryId;
}

class EntryShareCopyCubit extends Cubit<EntryShareCopyState> {
  EntryShareCopyCubit({
    required EntryShareCopyService service,
    required EntryShareSnapshot snapshot,
    required EntrySharingSession owner,
    required Future<EntrySharingSession?> Function() ownerReader,
    required Uint8List Function() copyMemberPrivateKey,
    required EntryShareLifetime lifetime,
    bool canCreateDefaultVault = false,
  }) : _service = service,
       _snapshot = snapshot,
       _owner = owner,
       _ownerReader = ownerReader,
       _copyMemberPrivateKey = copyMemberPrivateKey,
       _lifetime = lifetime,
       _canCreateDefaultVault = canCreateDefaultVault,
       super(const EntryShareCopyState()) {
    if (lifetime.isLive) {
      _expiry = Timer(lifetime.remaining, clear);
    } else {
      clear();
    }
  }

  final EntryShareCopyService _service;
  EntryShareSnapshot? _snapshot;
  final EntrySharingSession _owner;
  final Future<EntrySharingSession?> Function() _ownerReader;
  final Uint8List Function() _copyMemberPrivateKey;
  final EntryShareLifetime _lifetime;
  PreparedEntryShareCopy? _prepared;
  PreparedEntryShareDefaultVault? _preparedVault;
  final bool _canCreateDefaultVault;
  bool _emptyDestinations = false, _defaultVaultCreated = false;
  bool get canCreatePersonalVault =>
      _canCreateDefaultVault &&
      _emptyDestinations &&
      state.phase == EntryShareCopyPhase.editing &&
      !_loadingDestinations;
  CancelToken? _request;
  Uint8List? _privateKey;
  Timer? _expiry;
  int _epoch = 0;
  bool _loadingDestinations = false;

  Future<bool> revalidate() => _valid(_epoch);

  Future<EntryShareCopyDestinations> loadDestinations() async {
    if (_loadingDestinations || state.phase != EntryShareCopyPhase.editing) {
      throw const EntryShareCopyException(EntryShareCopyError.cancelled);
    }
    _loadingDestinations = true;
    _emptyDestinations = false;
    final epoch = _epoch;
    final request = _request = CancelToken();
    try {
      if (!await _valid(epoch)) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      final key = _privateKey = _copyMemberPrivateKey();
      final destinations = await _service.destinations(
        owner: _owner,
        memberPrivateKey: key,
        validateOwner: () => _valid(epoch),
        cancelToken: request,
      );
      if (!await _valid(epoch)) {
        throw const EntryShareCopyException(EntryShareCopyError.cancelled);
      }
      _emptyDestinations =
          destinations.items.isEmpty && destinations.unavailable == 0;
      return destinations;
    } finally {
      _wipeKey();
      _loadingDestinations = false;
    }
  }

  Future<bool> createPersonalVault(String name) async {
    if (!canCreatePersonalVault || isClosed) return false;
    final epoch = ++_epoch;
    final request = _request = CancelToken();
    emit(const EntryShareCopyState(phase: EntryShareCopyPhase.creatingVault));
    PreparedEntryShareDefaultVault? prepared;
    try {
      if (!await _valid(epoch)) return false;
      if (!_defaultVaultCreated) {
        if (_preparedVault == null) {
          final key = _privateKey = _copyMemberPrivateKey();
          prepared = await _service.prepareDefaultVault(
            owner: _owner,
            memberPrivateKey: key,
            name: name,
            validateOwner: () => _valid(epoch),
            cancelToken: request,
          );
          if (!await _valid(epoch)) return false;
          _preparedVault = prepared;
          prepared = null;
          _wipeKey();
        }
        _defaultVaultCreated = await _service.commitDefaultVault(
          _preparedVault!,
          validateOwner: () => _valid(epoch),
          cancelToken: request,
        );
        _preparedVault = null;
      }
      if (!await _valid(epoch)) return false;
      emit(const EntryShareCopyState());
      return true;
    } on EntryShareCopyException catch (error) {
      if (_preparedVault?.isDisposed == true) _preparedVault = null;
      if (!await _valid(epoch)) return false;
      if (error.kind == EntryShareCopyError.cancelled) {
        clear();
      } else {
        emit(const EntryShareCopyState(vaultCreationFailed: true));
      }
      return false;
    } catch (_) {
      if (await _valid(epoch)) {
        emit(const EntryShareCopyState(vaultCreationFailed: true));
      }
      return false;
    } finally {
      prepared?.dispose();
      _wipeKey();
    }
  }

  bool _live(int epoch) {
    if (isClosed ||
        epoch != _epoch ||
        state.phase == EntryShareCopyPhase.unavailable) {
      return false;
    }
    if (!_lifetime.isLive) {
      clear();
      return false;
    }
    return true;
  }

  Future<bool> _valid(int epoch) async {
    if (!_live(epoch)) return false;
    EntrySharingSession? current;
    try {
      current = await _ownerReader();
    } catch (_) {
      current = null;
    }
    if (!_live(epoch)) return false;
    if (current != _owner) {
      clear();
      return false;
    }
    return true;
  }

  Future<void> save({
    required String vaultId,
    String? title,
    Map<String, String> completedFields = const {},
  }) async {
    if (isClosed ||
        _loadingDestinations ||
        state.phase != EntryShareCopyPhase.editing ||
        _snapshot == null) {
      return;
    }
    final epoch = ++_epoch;
    final request = _request = CancelToken();
    emit(const EntryShareCopyState(phase: EntryShareCopyPhase.preparing));
    PreparedEntryShareCopy? prepared;
    try {
      if (!await _valid(epoch)) return;
      final key = _privateKey = _copyMemberPrivateKey();
      prepared = await _service.prepare(
        snapshot: _snapshot!,
        vaultId: vaultId,
        owner: _owner,
        memberPrivateKey: key,
        validateOwner: () => _valid(epoch),
        cancelToken: request,
        title: title,
        completedFields: completedFields,
      );
      if (!await _valid(epoch)) return;
      _prepared = prepared;
      prepared = null;
      _snapshot = null;
      _wipeKey();
      await _commit(epoch, request);
    } on EntryShareCopyInputException catch (error) {
      if (await _valid(epoch)) {
        emit(EntryShareCopyState(inputError: error.kind));
      }
    } on EntryShareCopyException catch (error) {
      if (error.kind == EntryShareCopyError.cancelled) {
        clear();
      } else if (await _valid(epoch)) {
        emit(const EntryShareCopyState(failed: true));
      }
    } catch (_) {
      if (await _valid(epoch)) emit(const EntryShareCopyState(failed: true));
    } finally {
      prepared?.dispose();
      _wipeKey();
    }
  }

  Future<void> retry() async {
    if (isClosed ||
        state.phase != EntryShareCopyPhase.retry ||
        _prepared == null) {
      return;
    }
    final epoch = ++_epoch;
    final request = _request = CancelToken();
    // Block a second tap synchronously, before any ownership read.
    emit(const EntryShareCopyState(phase: EntryShareCopyPhase.saving));
    await _commit(epoch, request);
  }

  Future<void> _commit(int epoch, CancelToken request) async {
    final copy = _prepared;
    if (copy == null) return;
    emit(const EntryShareCopyState(phase: EntryShareCopyPhase.saving));
    try {
      await _service.commit(
        copy,
        validateOwner: () => _valid(epoch),
        cancelToken: request,
      );
      if (!await _valid(epoch)) return;
      _prepared = null;
      copy.dispose();
      emit(
        EntryShareCopyState(
          phase: EntryShareCopyPhase.saved,
          vaultId: copy.vaultId,
          entryId: copy.entryId,
        ),
      );
    } catch (_) {
      if (!await _valid(epoch)) return;
      if (copy.isDisposed || request.isCancelled) {
        clear();
        return;
      }
      emit(
        const EntryShareCopyState(
          phase: EntryShareCopyPhase.retry,
          failed: true,
        ),
      );
    }
  }

  void _wipeKey() {
    final key = _privateKey;
    _privateKey = null;
    key?.fillRange(0, key.length, 0);
  }

  void clear() {
    _epoch++;
    _request?.cancel();
    _request = null;
    _expiry?.cancel();
    _expiry = null;
    _snapshot = null;
    _prepared?.dispose();
    _prepared = null;
    _preparedVault?.dispose();
    _preparedVault = null;
    _emptyDestinations = false;
    _wipeKey();
    _service.close();
    if (!isClosed) {
      emit(const EntryShareCopyState(phase: EntryShareCopyPhase.unavailable));
    }
  }

  @override
  Future<void> close() {
    clear();
    return super.close();
  }
}
