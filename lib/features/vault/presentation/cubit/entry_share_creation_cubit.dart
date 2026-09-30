import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/entry_sharing_remote_datasource.dart';
import '../../data/services/canonical_entry_detail_service.dart';
import '../../data/services/entry_sharing/entry_share_crypto_service.dart';
import '../../data/services/entry_sharing/entry_share_selection_service.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_creation.dart';
import '../../domain/entities/entry_share_list.dart';
import '../../domain/entities/entry_share_selection.dart';

enum EntryShareCreationPhase {
  initial,
  loading,
  ready,
  creating,
  retry,
  created,
  unavailable,
}

enum EntryShareCreationFailure { load, create, sourceChanged, invalidSelection }

final class CreatedEntryShareLink {
  const CreatedEntryShareLink({
    required this.shareId,
    required this.fragment,
    this.recipientEmail,
  });
  final String shareId, fragment;
  final String? recipientEmail;
}

final class EntryShareCreationState {
  const EntryShareCreationState({
    this.phase = EntryShareCreationPhase.initial,
    this.selection,
    this.failure,
    this.shareId,
    this.fragment,
    this.links = const [],
  });
  final EntryShareCreationPhase phase;
  final EntryShareSelection? selection;
  final EntryShareCreationFailure? failure;
  final String? shareId, fragment;
  final List<CreatedEntryShareLink> links;
}

class EntryShareCreationCubit extends Cubit<EntryShareCreationState> {
  EntryShareCreationCubit({
    required EntrySharingRemoteDatasource remote,
    required EntryShareCryptoService crypto,
    required EntryEntity expected,
    required Future<EntrySharingSession?> Function() sessionReader,
    required Future<CanonicalEntrySnapshot> Function() sourceReader,
    DateTime Function()? now,
  }) : _remote = remote,
       _crypto = crypto,
       _expected = expected,
       _sessionReader = sessionReader,
       _sourceReader = sourceReader,
       _now = now ?? DateTime.now,
       super(const EntryShareCreationState());

  final EntrySharingRemoteDatasource _remote;
  final EntryShareCryptoService _crypto;
  final EntryEntity _expected;
  final Future<EntrySharingSession?> Function() _sessionReader;
  final Future<CanonicalEntrySnapshot> Function() _sourceReader;
  final DateTime Function() _now;
  EntrySharingSession? _owner;
  PreparedEntryShare? _material;
  EntryShareCreationRequest? _prepared;
  EntryShareCreationOptions? _batchOptions;
  EntryShareSelection? _batchSelection;
  final List<CreatedEntryShareLink> _createdLinks = [];
  int _nextRecipient = 0;
  CancelToken? _request;
  Timer? _expiry;
  int _epoch = 0;

  Future<bool> _valid(int epoch, {bool bind = false}) async {
    if (isClosed || epoch != _epoch) return false;
    EntrySharingSession? current;
    try {
      current = await _sessionReader();
    } catch (_) {
      current = null;
    }
    if (isClosed || epoch != _epoch) return false;
    if (bind && _owner == null) _owner = current;
    if (current == null || current != _owner) {
      clear();
      return false;
    }
    return true;
  }

  Future<void> load() async {
    if (isClosed || state.phase != EntryShareCreationPhase.initial) return;
    final epoch = ++_epoch;
    emit(const EntryShareCreationState(phase: EntryShareCreationPhase.loading));
    CanonicalEntrySnapshot? source;
    try {
      if (!await _valid(epoch, bind: true)) return;
      source = await _sourceReader();
      if (!await _valid(epoch)) return;
      // The requested Entry and authenticated session independently bind plaintext.
      if (source.entry['id'] != _expected.id ||
          source.entry['vaultId'] != _expected.vaultId ||
          source.entry['organizationId'] != _owner!.organizationId ||
          source.entry['currentRevision'] != _expected.currentRevision) {
        clear(failure: EntryShareCreationFailure.sourceChanged);
        return;
      }
      final selection = const EntryShareSelectionService().project(source);
      emit(
        EntryShareCreationState(
          phase: EntryShareCreationPhase.ready,
          selection: selection,
        ),
      );
    } catch (_) {
      if (!await _valid(epoch)) return;
      emit(
        const EntryShareCreationState(failure: EntryShareCreationFailure.load),
      );
    } finally {
      source?.clear();
    }
  }

  Future<void> create({required EntryShareCreationOptions options}) async {
    if (isClosed || state.phase != EntryShareCreationPhase.ready) return;
    final selection = state.selection!;
    EntryShareSnapshot snapshot;
    try {
      snapshot = selection.wholeEntry();
    } on EntryShareException {
      emit(
        EntryShareCreationState(
          phase: EntryShareCreationPhase.ready,
          selection: selection,
          failure: EntryShareCreationFailure.invalidSelection,
        ),
      );
      return;
    }
    _batchOptions = options;
    _batchSelection = selection;
    _nextRecipient = 0;
    _createdLinks.clear();
    final epoch = ++_epoch;
    final token = _request = CancelToken();
    emit(
      EntryShareCreationState(
        phase: EntryShareCreationPhase.creating,
        selection: selection,
      ),
    );
    try {
      await _createRemaining(epoch, token, snapshot);
    } finally {
      if (identical(_request, token)) _request = null;
    }
  }

  Future<void> retry() async {
    if (isClosed || state.phase != EntryShareCreationPhase.retry) return;
    final epoch = ++_epoch;
    final token = _request = CancelToken();
    emit(
      const EntryShareCreationState(phase: EntryShareCreationPhase.creating),
    );
    try {
      if (!await _valid(epoch)) return;
      if (_prepared != null) {
        await _send(epoch, token);
      }
      if (_prepared == null && _nextRecipient < _recipientCount) {
        await _createRemaining(epoch, token, _batchSelection!.wholeEntry());
      }
      if (state.phase == EntryShareCreationPhase.created) {
        _batchSelection = null;
        _batchOptions = null;
      }
    } finally {
      if (identical(_request, token)) _request = null;
    }
  }

  Future<bool> revalidate() => _valid(_epoch);

  Future<String?> fragmentForCopy([int index = 0]) async {
    if (state.phase != EntryShareCreationPhase.created &&
            state.phase != EntryShareCreationPhase.retry ||
        !await _valid(_epoch)) {
      return null;
    }
    return index < 0 || index >= state.links.length
        ? null
        : state.links[index].fragment;
  }

  int get _recipientCount =>
      _batchOptions!.recipientMode == EntryShareRecipientMode.namedRecipient
      ? _batchOptions!.recipientEmails.length
      : 1;

  bool get hasMultipleRequestedRecipients {
    final options = _batchOptions;
    return options == null
        ? _createdLinks.length > 1
        : options.recipientMode == EntryShareRecipientMode.namedRecipient &&
              options.recipientEmails.length > 1;
  }

  Future<void> _createRemaining(
    int epoch,
    CancelToken token,
    EntryShareSnapshot snapshot,
  ) async {
    while (_nextRecipient < _recipientCount) {
      PreparedEntryShare? material;
      try {
        if (!await _valid(epoch)) return;
        final challenge = await _remote.challenge(
          _expected.vaultId,
          _expected.id,
          cancelToken: token,
        );
        if (!await _valid(epoch)) return;
        if (challenge.sourceRevision != _expected.currentRevision) {
          clear(failure: EntryShareCreationFailure.sourceChanged);
          return;
        }
        final expires = _now().toUtc().add(
          Duration(hours: _batchOptions!.lifetimeHours),
        );
        final scope = EntryShareScope(
          shareId: challenge.shareId,
          organizationId: _owner!.organizationId,
          vaultId: _expected.vaultId,
          entryId: _expected.id,
          sourceRevision: _expected.currentRevision,
          expiresAt: expires.toIso8601String(),
        );
        material = await _crypto.prepare(scope: scope, snapshot: snapshot);
        if (!await _valid(epoch)) return;
        _material = material;
        final recipient =
            _batchOptions!.recipientMode ==
                EntryShareRecipientMode.namedRecipient
            ? _batchOptions!.recipientEmails[_nextRecipient]
            : null;
        _prepared = EntryShareCreationRequest(
          shareId: scope.shareId,
          sourceRevision: scope.sourceRevision,
          expiresAt: scope.expiresAt,
          options: recipient == null
              ? _batchOptions!
              : _batchOptions!.forRecipient(recipient),
          accessToken: base64UrlEncode(
            material.secrets.accessToken,
          ).replaceAll('=', ''),
          packet: material.packet,
        );
        _expiry ??= Timer(expires.difference(_now().toUtc()), clear);
        await _send(epoch, token);
        if (state.phase == EntryShareCreationPhase.retry ||
            state.phase == EntryShareCreationPhase.unavailable) {
          return;
        }
      } catch (_) {
        if (!await _valid(epoch)) return;
        if (_createdLinks.isEmpty) {
          _expiry?.cancel();
          _expiry = null;
        }
        _material?.dispose();
        _material = null;
        _prepared = null;
        emit(
          EntryShareCreationState(
            phase: _createdLinks.isEmpty
                ? EntryShareCreationPhase.ready
                : EntryShareCreationPhase.retry,
            selection: _createdLinks.isEmpty ? _batchSelection : null,
            failure: EntryShareCreationFailure.create,
            links: List.unmodifiable(_createdLinks),
          ),
        );
        return;
      } finally {
        if (!identical(_material, material)) material?.dispose();
      }
    }
    _batchSelection = null;
    _batchOptions = null;
  }

  Future<void> _send(int epoch, CancelToken token) async {
    final prepared = _prepared!;
    try {
      await _remote.create(
        _expected.vaultId,
        _expected.id,
        prepared,
        cancelToken: token,
      );
      if (!await _valid(epoch)) return;
      final fragment = _material!.secrets.toFragment();
      _createdLinks.add(
        CreatedEntryShareLink(
          shareId: prepared.shareId,
          fragment: fragment,
          recipientEmail: prepared.options.recipientEmail,
        ),
      );
      _material?.dispose();
      _material = null;
      _prepared = null;
      _nextRecipient++;
      emit(
        EntryShareCreationState(
          phase: _nextRecipient == _recipientCount
              ? EntryShareCreationPhase.created
              : EntryShareCreationPhase.creating,
          shareId: _createdLinks.first.shareId,
          fragment: _createdLinks.first.fragment,
          links: List.unmodifiable(_createdLinks),
        ),
      );
    } catch (_) {
      if (!await _valid(epoch)) return;
      emit(
        EntryShareCreationState(
          phase: EntryShareCreationPhase.retry,
          failure: EntryShareCreationFailure.create,
          links: List.unmodifiable(_createdLinks),
        ),
      );
    }
  }

  void clear({EntryShareCreationFailure? failure}) {
    _epoch++;
    _request?.cancel();
    _request = null;
    _expiry?.cancel();
    _expiry = null;
    _material?.dispose();
    _material = null;
    _prepared = null;
    _batchOptions = null;
    _batchSelection = null;
    _createdLinks.clear();
    _nextRecipient = 0;
    if (!isClosed) {
      emit(
        EntryShareCreationState(
          phase: EntryShareCreationPhase.unavailable,
          failure: failure,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    clear();
    return super.close();
  }
}
