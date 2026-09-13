import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/utils/request_id.dart';
import '../data/consent_activation_store.dart';
import '../data/consent_remote_datasource.dart';
import '../domain/user_consent.dart';

class ConsentState {
  const ConsentState({
    this.userId,
    this.consents = const [],
    this.loading = false,
    this.saving = false,
    this.error,
    this.failedDecision,
    this.locallyActive = false,
    this.requiresReconfirmation = false,
  });
  final String? userId;
  final List<UserConsent> consents;
  final bool loading;
  final bool saving;
  final ConsentErrorKind? error;
  final ConsentDecision? failedDecision;
  final bool locallyActive;
  final bool requiresReconfirmation;
}

/// Session-bound account preferences and expiring client-analytics authority.
/// The backend owns revisions and decisions; local state never predicts them.
class ConsentCubit extends Cubit<ConsentState> {
  ConsentCubit(
    this._remote,
    this._store,
    this._analytics, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const ConsentState());
  final ConsentRemoteDataSource _remote;
  final ConsentActivationStore _store;
  final AnalyticsService _analytics;
  final DateTime Function() _now;
  String? _userId;
  String _locale = 'en';
  int _generation = 0;
  int _readVersion = 0;
  int _activationVersion = 0;
  final _blockedAccounts = <String>{};
  bool _foreground = true;
  ConsentActivation? _activation;
  Timer? _poll;
  CancelToken? _read;
  CancelToken? _write;

  Future<void> bind(String? userId, String locale) async {
    if (_userId == userId && _locale == locale) return;
    final accountChanged = _userId != userId;
    _userId = userId;
    _locale = locale;
    final generation = ++_generation;
    _readVersion++;
    _read?.cancel();
    _write?.cancel();
    _poll?.cancel();
    final activationVersion = _activationVersion;
    _activation = null;
    await _analytics.reset();
    if (isClosed || generation != _generation) return;
    emit(ConsentState(userId: userId, loading: userId != null));
    if (userId == null) return;
    ConsentActivation? activation;
    try {
      activation = await _store.read(userId);
    } catch (_) {
      activation = null;
    }
    if (generation != _generation || isClosed) return;
    if (activationVersion == _activationVersion &&
        !_blockedAccounts.contains(userId)) {
      _activation = activation;
    }
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
    // Account changes never inherit another principal's local activation.
    if (accountChanged || _foreground) await refresh();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      _readVersion++;
      _read?.cancel();
      unawaited(_analytics.reset());
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null || !_foreground || state.saving || isClosed) return;
    final generation = _generation;
    final version = ++_readVersion;
    _read?.cancel();
    final cancellation = _read = CancelToken();
    final observedAt = _now();
    try {
      final response = await _remote.get(_locale, cancelToken: cancellation);
      if (generation != _generation ||
          version != _readVersion ||
          isClosed ||
          !_foreground) {
        return;
      }
      final analyticsConsent = response.consents
          .where((value) => value.purpose == 'product_analytics')
          .firstOrNull;
      if (analyticsConsent != null && !analyticsConsent.granted) {
        _stopMemory();
        try {
          await _store.write(userId, null);
        } catch (_) {
          /* stays off */
        }
      }
      if (generation != _generation ||
          version != _readVersion ||
          isClosed ||
          !_foreground) {
        return;
      }
      final locallyActive =
          !_blockedAccounts.contains(userId) &&
          analyticsConsent != null &&
          analyticsConsent.granted &&
          analyticsConsent.currentNotice?.version ==
              analyticsConsent.noticeVersion &&
          _activation?.noticeVersion == analyticsConsent.noticeVersion &&
          _activation?.revision == analyticsConsent.activationRevision;
      if (locallyActive) {
        _analytics.authorize(
          userId,
          observedAt.add(Duration(seconds: response.maxAgeSeconds)),
          () =>
              !isClosed &&
              _foreground &&
              generation == _generation &&
              _userId == userId &&
              !_blockedAccounts.contains(userId) &&
              _activation?.revision == analyticsConsent.activationRevision &&
              _activation?.noticeVersion == analyticsConsent.noticeVersion,
        );
      } else {
        unawaited(_analytics.reset());
      }
      emit(
        ConsentState(
          userId: userId,
          consents: response.consents,
          locallyActive: locallyActive,
          error: state.failedDecision == null ? null : ConsentErrorKind.save,
          requiresReconfirmation: state.requiresReconfirmation,
          failedDecision: state.failedDecision,
        ),
      );
    } catch (_) {
      if (generation != _generation || version != _readVersion || isClosed) {
        return;
      }
      unawaited(_analytics.reset());
      emit(
        ConsentState(
          userId: userId,
          consents: state.consents,
          error: ConsentErrorKind.load,
          requiresReconfirmation: state.requiresReconfirmation,
          failedDecision: state.failedDecision,
        ),
      );
    }
  }

  void _stopMemory() {
    _activationVersion++;
    if (_userId case final userId?) _blockedAccounts.add(userId);
    _activation = null;
    unawaited(_analytics.reset());
  }

  /// Stop locally before an API decision or dismissal; never treat this as an account withdrawal.
  Future<void> stopHere() async {
    _stopMemory();
    final userId = _userId;
    if (!isClosed) {
      emit(
        ConsentState(
          userId: userId,
          consents: state.consents,
          loading: state.loading,
          saving: state.saving,
          error: state.error,
          requiresReconfirmation: state.requiresReconfirmation,
          failedDecision: state.failedDecision,
        ),
      );
    }
    if (userId != null) {
      try {
        await _store.write(userId, null);
      } catch (_) {
        /* remains off */
      }
    }
  }

  ConsentDecision? decision(UserConsent consent, bool granted, String source) {
    final version = consent.currentNotice?.version ?? consent.noticeVersion;
    final locale = consent.currentNotice?.locale ?? consent.noticeLocale;
    if (version == null || locale == null) return null;
    return ConsentDecision(
      purpose: consent.purpose,
      granted: granted,
      expectedRevision: consent.revision,
      requestId: newRequestId(),
      noticeVersion: version,
      locale: locale,
      source: source,
    );
  }

  Future<bool> save(ConsentDecision decision) async {
    final userId = _userId;
    if (userId == null || state.saving || isClosed) return false;
    final generation = _generation;
    _readVersion++;
    _read?.cancel();
    final cancellation = _write = CancelToken();
    final analyticsPurpose = decision.purpose == 'product_analytics';
    if (analyticsPurpose) _stopMemory();
    final activationVersion = _activationVersion;
    emit(
      ConsentState(
        userId: userId,
        consents: state.consents,
        saving: true,
        locallyActive: analyticsPurpose ? false : state.locallyActive,
      ),
    );
    try {
      if (analyticsPurpose) {
        try {
          await _store.write(userId, null);
        } catch (_) {
          /* Still attempt the account withdrawal. */
        }
      }
      if (generation != _generation || cancellation.isCancelled) return false;
      final result = await _remote.decide(decision, cancelToken: cancellation);
      if (generation != _generation || isClosed) return false;
      if (analyticsPurpose &&
          activationVersion == _activationVersion &&
          decision.granted &&
          result.granted &&
          result.revision == decision.expectedRevision + 1 &&
          result.noticeVersion == decision.noticeVersion) {
        final activation = ConsentActivation(
          result.noticeVersion!,
          result.activationRevision,
        );
        await _store.write(userId, activation);
        if (generation != _generation ||
            activationVersion != _activationVersion ||
            isClosed) {
          try {
            await _store.write(userId, null);
          } catch (_) {
            /* no in-memory activation */
          }
        } else {
          _blockedAccounts.remove(userId);
          _activation = activation;
        }
      }
      if (generation != _generation || isClosed) return false;
      emit(ConsentState(userId: userId, consents: state.consents));
      await refresh();
      if (generation != _generation || isClosed) return false;
      if (state.error == ConsentErrorKind.load) {
        emit(
          ConsentState(
            userId: userId,
            consents: state.consents,
            error: ConsentErrorKind.load,
            failedDecision: decision,
          ),
        );
      }
      return state.error == null;
    } catch (error) {
      if (generation != _generation || isClosed) return false;
      _stopMemory();
      final status = error is DioException ? error.response?.statusCode : null;
      // A definite rejection cannot become valid by replaying the same request.
      final rejected =
          status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429;
      final conflict = status == 409;
      emit(
        ConsentState(
          userId: userId,
          consents: state.consents,
          error: ConsentErrorKind.save,
          failedDecision: rejected ? null : decision,
          requiresReconfirmation: conflict,
        ),
      );
      if (rejected) await refresh();
      return false;
    }
  }

  @override
  Future<void> close() {
    _generation++;
    _readVersion++;
    _read?.cancel();
    _write?.cancel();
    _poll?.cancel();
    unawaited(_analytics.reset());
    return super.close();
  }
}
