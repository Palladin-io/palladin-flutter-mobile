import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/entry_share_recipient_datasource.dart';
import '../../data/services/entry_sharing/entry_share_crypto_service.dart';
import '../../data/services/entry_sharing/entry_share_lifetime.dart';
import '../../data/services/entry_sharing/entry_share_secrets.dart';
import '../../data/services/vault_protocol/vault_protocol_bytes.dart';
import '../../domain/entities/entry_share.dart';
import '../../domain/entities/entry_share_reception.dart';

export '../../domain/entities/entry_share_reception.dart'
    show EntryShareRecipientOwner;

enum EntryShareReceptionPhase {
  welcome,
  verification,
  received,
  ended,
  unavailable,
}

enum EntryShareReceptionOutcome { completed, failed, cancelled, ignored }

enum EntryShareConfirmation { pending, confirmed, failed }

final class EntryShareReceptionState {
  const EntryShareReceptionState({
    this.phase = EntryShareReceptionPhase.welcome,
    this.busy = false,
    this.suspended = false,
    this.recipientMode = '',
    this.protection = '',
    this.shareExpiresAt,
    this.maximumReceipts,
    this.otpRetryAfterSeconds = 0,
    this.otpRequested = false,
    this.otpRetry = false,
    this.emailVerified = false,
    this.secretVerified = false,
    this.snapshot,
    this.confirmation = EntryShareConfirmation.pending,
  });

  final EntryShareReceptionPhase phase;
  final bool busy, otpRequested, otpRetry, emailVerified, secretVerified;
  final bool suspended;
  final String recipientMode, protection;
  final String? shareExpiresAt;
  final int? maximumReceipts;
  final int otpRetryAfterSeconds;
  final EntryShareSnapshot? snapshot;
  final EntryShareConfirmation confirmation;

  bool get gatesReady =>
      (recipientMode == 'anyoneWithLink' ||
          recipientMode == 'namedRecipient' && emailVerified) &&
      (protection == 'none' ||
          {'password', 'pin'}.contains(protection) && secretVerified);

  EntryShareReceptionState copyWith({
    EntryShareReceptionPhase? phase,
    bool? busy,
    bool? suspended,
    String? recipientMode,
    String? protection,
    String? shareExpiresAt,
    int? maximumReceipts,
    int? otpRetryAfterSeconds,
    bool? otpRequested,
    bool? otpRetry,
    bool? emailVerified,
    bool? secretVerified,
    EntryShareSnapshot? snapshot,
    EntryShareConfirmation? confirmation,
  }) => EntryShareReceptionState(
    phase: phase ?? this.phase,
    busy: busy ?? this.busy,
    suspended: suspended ?? this.suspended,
    recipientMode: recipientMode ?? this.recipientMode,
    protection: protection ?? this.protection,
    shareExpiresAt: shareExpiresAt ?? this.shareExpiresAt,
    maximumReceipts: maximumReceipts ?? this.maximumReceipts,
    otpRetryAfterSeconds: otpRetryAfterSeconds ?? this.otpRetryAfterSeconds,
    otpRequested: otpRequested ?? this.otpRequested,
    otpRetry: otpRetry ?? this.otpRetry,
    emailVerified: emailVerified ?? this.emailVerified,
    secretVerified: secretVerified ?? this.secretVerified,
    snapshot: snapshot ?? this.snapshot,
    confirmation: confirmation ?? this.confirmation,
  );
}

class EntryShareReceptionCubit extends Cubit<EntryShareReceptionState> {
  EntryShareReceptionCubit({
    required EntryShareRecipientDatasource remote,
    required EntryShareCryptoService crypto,
    required String shareId,
    required EntryShareSecrets secrets,
    required EntryShareRecipientOwner owner,
    required Future<EntryShareRecipientOwner?> Function() ownerReader,
    DateTime Function()? now,
    Duration Function()? elapsed,
    EntryShareLifetime? lifetime,
  }) : _remote = remote,
       _crypto = crypto,
       _shareId = shareId,
       _secrets = secrets,
       _owner = owner,
       _ownerReader = ownerReader,
       _lifetime = lifetime ?? EntryShareLifetime(now: now, elapsed: elapsed),
       super(const EntryShareReceptionState()) {
    if (_lifetime.isLive) {
      _expiry = Timer(_lifetime.remaining, clear);
    } else {
      clear();
    }
  }

  EntryShareRecipientDatasource? _remote;
  final EntryShareCryptoService _crypto;
  final String _shareId;
  final EntryShareRecipientOwner _owner;
  final Future<EntryShareRecipientOwner?> Function() _ownerReader;
  final EntryShareLifetime _lifetime;
  EntryShareLifetime get lifetime => _lifetime;
  EntryShareRecipientOwner get owner => _owner;
  EntryShareSecrets? _secrets;
  EntryShareRecipientSession? _session;
  final _cancel = CancelToken();
  Timer? _expiry;
  Timer? _otpCountdown;
  Duration? _otpReadyAtRemaining;
  int _epoch = 0, _otpGeneration = 0;
  int _visibilityGeneration = 0;
  int? _pendingOtp;

  bool _live(int epoch) {
    if (isClosed || epoch != _epoch || _secrets == null) return false;
    if (!_lifetime.isLive) {
      clear();
      return false;
    }
    return true;
  }

  Future<bool> _valid(int epoch) async {
    if (!_live(epoch)) return false;
    EntryShareRecipientOwner? current;
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

  Future<bool> revalidate() => _valid(_epoch);

  Future<EntryShareReceptionTransfer?> detachForAccount() async {
    if (isClosed || state.busy || state.suspended || !_live(_epoch)) {
      return null;
    }
    final epoch = _epoch;
    emit(state.copyWith(busy: true));
    if (!await _valid(epoch)) return null;
    final transfer = EntryShareReceptionTransfer._(
      remote: _remote!,
      crypto: _crypto,
      shareId: _shareId,
      secrets: _secrets!,
      initialOwner: _owner,
      lifetime: _lifetime,
      session: _session,
      state: state.copyWith(busy: false),
      otpGeneration: _otpGeneration,
      pendingOtp: _pendingOtp,
      otpReadyAtRemaining: _otpReadyAtRemaining,
    );
    _remote = null;
    _secrets = null;
    clear();
    return transfer;
  }

  static EntryShareReceptionCubit? _resume(
    EntryShareReceptionTransfer transfer,
    EntryShareRecipientOwner owner,
    Future<EntryShareRecipientOwner?> Function() ownerReader,
  ) {
    final result = EntryShareReceptionCubit(
      remote: transfer._remote!,
      crypto: transfer._crypto,
      shareId: transfer._shareId,
      secrets: transfer._secrets!,
      owner: owner,
      ownerReader: ownerReader,
      lifetime: transfer._lifetime,
    );
    if (result._live(result._epoch)) {
      result._session = transfer._session;
      result._otpGeneration = transfer._otpGeneration;
      result._pendingOtp = transfer._pendingOtp;
      result._otpReadyAtRemaining = transfer._otpReadyAtRemaining;
      result.emit(transfer._state!);
      result._refreshOtpCountdown();
    }
    transfer._remote = null;
    transfer._secrets = null;
    transfer.dispose();
    if (result.state.phase == EntryShareReceptionPhase.unavailable) {
      unawaited(result.close());
      return null;
    }
    return result;
  }

  bool suspendForEmail() {
    if (!_live(_epoch) ||
        state.phase != EntryShareReceptionPhase.verification ||
        state.recipientMode != 'namedRecipient' ||
        !state.otpRequested ||
        state.otpRetry ||
        state.emailVerified ||
        state.busy ||
        state.snapshot != null) {
      return false;
    }
    // Checking another app's email must not create a new receipt or extend TTL.
    _visibilityGeneration++;
    _otpCountdown?.cancel();
    emit(state.copyWith(suspended: true));
    return true;
  }

  Future<void> resumeFromEmail() async {
    if (!state.suspended) return;
    final visibility = _visibilityGeneration;
    if (await _valid(_epoch) && visibility == _visibilityGeneration) {
      emit(state.copyWith(suspended: false));
      _refreshOtpCountdown();
    }
  }

  Future<EntryShareReceptionOutcome> _run(
    Future<void> Function(int) action,
  ) async {
    if (isClosed || state.busy || state.suspended || _secrets == null) {
      return EntryShareReceptionOutcome.ignored;
    }
    final epoch = _epoch;
    emit(state.copyWith(busy: true));
    try {
      if (!await _valid(epoch)) return EntryShareReceptionOutcome.cancelled;
      await action(epoch);
      if (state.phase == EntryShareReceptionPhase.ended) {
        return EntryShareReceptionOutcome.completed;
      }
      return await _valid(epoch)
          ? EntryShareReceptionOutcome.completed
          : EntryShareReceptionOutcome.cancelled;
    } catch (_) {
      return await _valid(epoch)
          ? EntryShareReceptionOutcome.failed
          : EntryShareReceptionOutcome.cancelled;
    } finally {
      if (_live(epoch)) emit(state.copyWith(busy: false));
    }
  }

  Future<EntryShareReceptionOutcome> open() {
    if (state.phase != EntryShareReceptionPhase.welcome) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      final session = await _remote!.open(
        _shareId,
        VaultProtocolBytes.base64UrlEncode(_secrets!.accessToken),
        cancelToken: _cancel,
      );
      if (!await _valid(epoch)) return;
      final expires = DateTime.tryParse(session.expiresAt);
      if (expires == null) {
        clear();
        return;
      }
      _lifetime.shortenTo(expires);
      if (!_lifetime.isLive) {
        clear();
        return;
      }
      _expiry?.cancel();
      _expiry = Timer(_lifetime.remaining, clear);
      _session = session;
      emit(
        state.copyWith(
          phase: EntryShareReceptionPhase.verification,
          recipientMode: session.recipientMode,
          protection: session.protection,
          shareExpiresAt: session.shareExpiresAt,
          maximumReceipts: session.maximumReceipts,
        ),
      );
      _setOtpCooldown(Duration(seconds: session.otpRetryAfterSeconds));
    });
  }

  Future<EntryShareReceptionOutcome> requestOtp(String language) {
    if (_session == null ||
        state.recipientMode != 'namedRecipient' ||
        state.emailVerified ||
        _pendingOtp == null && _otpSecondsRemaining > 0) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      _pendingOtp ??= _otpGeneration + 1;
      emit(state.copyWith(otpRetry: true));
      final cooldown = await _remote!.requestOtp(
        _shareId,
        _session!,
        generation: _pendingOtp!,
        language: language,
        cancelToken: _cancel,
      );
      if (!await _valid(epoch)) return;
      _otpGeneration = _pendingOtp!;
      _pendingOtp = null;
      emit(state.copyWith(otpRequested: true, otpRetry: false));
      _setOtpCooldown(cooldown);
    });
  }

  int get _otpSecondsRemaining {
    final readyAt = _otpReadyAtRemaining;
    if (readyAt == null) return 0;
    final remaining = _lifetime.remaining - readyAt;
    return remaining <= Duration.zero
        ? 0
        : (remaining.inMicroseconds / Duration.microsecondsPerSecond).ceil();
  }

  void _setOtpCooldown(Duration cooldown) {
    _otpReadyAtRemaining = _lifetime.remaining - cooldown;
    _refreshOtpCountdown();
  }

  void _refreshOtpCountdown() {
    _otpCountdown?.cancel();
    _otpCountdown = null;
    if (!_live(_epoch) || state.suspended) return;
    final seconds = state.emailVerified ? 0 : _otpSecondsRemaining;
    if (seconds != state.otpRetryAfterSeconds) {
      emit(state.copyWith(otpRetryAfterSeconds: seconds));
    }
    if (seconds > 0 && state.recipientMode == 'namedRecipient') {
      _otpCountdown = Timer(const Duration(seconds: 1), _refreshOtpCountdown);
    }
  }

  Future<EntryShareReceptionOutcome> verifyOtp(String code) {
    if (_session == null ||
        _otpGeneration == 0 ||
        _pendingOtp != null ||
        state.emailVerified) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      await _remote!.verifyOtp(
        _shareId,
        _session!,
        generation: _otpGeneration,
        code: code,
        cancelToken: _cancel,
      );
      if (await _valid(epoch)) {
        emit(state.copyWith(emailVerified: true));
        _refreshOtpCountdown();
      }
    });
  }

  Future<EntryShareReceptionOutcome> verifySecret(String secret) {
    if (_session == null ||
        !{'password', 'pin'}.contains(state.protection) ||
        state.secretVerified) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      await _remote!.verifySecret(
        _shareId,
        _session!,
        secret: secret,
        cancelToken: _cancel,
      );
      if (await _valid(epoch)) emit(state.copyWith(secretVerified: true));
    });
  }

  Future<EntryShareReceptionOutcome> receive() {
    if (_session == null || !state.gatesReady || state.snapshot != null) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      final delivery = await _remote!.receive(
        _shareId,
        _session!,
        cancelToken: _cancel,
      );
      if (!await _valid(epoch)) return;
      EntryShareSnapshot snapshot;
      try {
        snapshot = await _crypto.open(
          packet: delivery.packet,
          authority: delivery.authority,
          requestedShareId: _shareId,
          key: _secrets!.key,
        );
      } catch (_) {
        if (await _valid(epoch)) clear();
        return;
      }
      if (await _valid(epoch)) {
        emit(
          state.copyWith(
            phase: EntryShareReceptionPhase.received,
            snapshot: snapshot,
          ),
        );
      }
    });
  }

  Future<EntryShareReceptionOutcome> confirmDisplay() {
    if (_session == null ||
        state.snapshot == null ||
        state.confirmation == EntryShareConfirmation.confirmed) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      try {
        await _remote!.confirmDisplay(
          _shareId,
          _session!,
          cancelToken: _cancel,
        );
      } catch (_) {
        if (await _valid(epoch)) {
          emit(state.copyWith(confirmation: EntryShareConfirmation.failed));
        }
        rethrow;
      }
      if (await _valid(epoch)) {
        emit(state.copyWith(confirmation: EntryShareConfirmation.confirmed));
      }
    });
  }

  Future<EntryShareReceptionOutcome> end() {
    if (_session == null || !state.gatesReady) {
      return Future.value(EntryShareReceptionOutcome.ignored);
    }
    return _run((epoch) async {
      await _remote!.end(_shareId, _session!, cancelToken: _cancel);
      if (await _valid(epoch)) clear(ended: true);
    });
  }

  void clear({bool ended = false}) {
    _epoch++;
    _cancel.cancel();
    _remote?.close();
    _remote = null;
    _expiry?.cancel();
    _expiry = null;
    _otpCountdown?.cancel();
    _otpCountdown = null;
    _otpReadyAtRemaining = null;
    _secrets?.dispose();
    _secrets = null;
    _session = null;
    _pendingOtp = null;
    _otpGeneration = 0;
    if (!isClosed) {
      emit(
        EntryShareReceptionState(
          phase: ended
              ? EntryShareReceptionPhase.ended
              : EntryShareReceptionPhase.unavailable,
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

/// A one-shot RAM owner used only after an explicit account-continuation action.
/// The app-level coordinator must dispose it on abandonment or session loss.
final class EntryShareReceptionTransfer {
  EntryShareReceptionTransfer._({
    required EntryShareRecipientDatasource remote,
    required EntryShareCryptoService crypto,
    required String shareId,
    required EntryShareSecrets secrets,
    required this.initialOwner,
    required EntryShareLifetime lifetime,
    required EntryShareRecipientSession? session,
    required EntryShareReceptionState state,
    required int otpGeneration,
    required int? pendingOtp,
    required Duration? otpReadyAtRemaining,
  }) : _remote = remote,
       _crypto = crypto,
       _shareId = shareId,
       _secrets = secrets,
       _lifetime = lifetime,
       _session = session,
       _state = state,
       _otpGeneration = otpGeneration,
       _pendingOtp = pendingOtp,
       _otpReadyAtRemaining = otpReadyAtRemaining {
    _expiry = Timer(lifetime.remaining, dispose);
  }

  EntryShareRecipientDatasource? _remote;
  final EntryShareCryptoService _crypto;
  final String _shareId;
  EntryShareSecrets? _secrets;
  final EntryShareRecipientOwner initialOwner;
  final EntryShareLifetime _lifetime;
  EntryShareRecipientSession? _session;
  EntryShareReceptionState? _state;
  final int _otpGeneration;
  int? _pendingOtp;
  final Duration? _otpReadyAtRemaining;
  Timer? _expiry;
  bool _resuming = false;

  Duration get remaining => _lifetime.remaining;

  bool get isAvailable {
    if (!_lifetime.isLive) dispose();
    return _secrets != null;
  }

  Future<EntryShareReceptionCubit?> resume({
    required EntryShareRecipientOwner owner,
    required Future<EntryShareRecipientOwner?> Function() ownerReader,
  }) async {
    if (_resuming || !isAvailable) return null;
    _resuming = true;
    try {
      if (owner.principalId == null ||
          owner.organizationId == null ||
          owner.authorizationGeneration == null ||
          initialOwner.principalId != null &&
              (owner.principalId != initialOwner.principalId ||
                  owner.organizationId != initialOwner.organizationId)) {
        dispose();
        return null;
      }
      final current = await ownerReader();
      if (!isAvailable) return null;
      if (current != owner) {
        dispose();
        return null;
      }
      return EntryShareReceptionCubit._resume(this, owner, ownerReader);
    } catch (_) {
      dispose();
      return null;
    } finally {
      _resuming = false;
    }
  }

  void dispose() {
    _expiry?.cancel();
    _expiry = null;
    _remote?.close();
    _remote = null;
    _secrets?.dispose();
    _secrets = null;
    _session = null;
    _state = null;
    _pendingOtp = null;
  }
}
