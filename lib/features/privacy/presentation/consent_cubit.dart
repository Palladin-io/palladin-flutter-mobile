import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/utils/request_id.dart';
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
    this.analyticsAuthorized = false,
    this.requiresReconfirmation = false,
    this.saveFailed = false,
  });
  final String? userId;
  final List<UserConsent> consents;
  final bool loading;
  final bool saving;
  final ConsentErrorKind? error;
  final ConsentDecision? failedDecision;
  final bool analyticsAuthorized;
  final bool requiresReconfirmation;
  // A rejected write remains a failure even when its request cannot be retried.
  final bool saveFailed;
}

/// Session-bound account preferences and expiring client-analytics authority.
/// The backend owns revisions and decisions; local state never predicts them.
class ConsentCubit extends Cubit<ConsentState> {
  ConsentCubit(this._remote, this._analytics, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const ConsentState());
  final ConsentRemoteDataSource _remote;
  final AnalyticsService _analytics;
  final DateTime Function() _now;
  String? _userId;
  String _locale = 'en';
  int _generation = 0;
  int _readVersion = 0;
  final _pauses = <Object>{};
  // Presentation history only: opening settings never grants consent or capture.
  final _offeredChoices = <String>{};
  bool hasOfferedChoices(String userId) => _offeredChoices.contains(userId);
  void markChoicesOffered(String userId) => _offeredChoices.add(userId);
  bool _foreground = true;
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
    _pauses.clear();
    await _analytics.reset();
    if (isClosed || generation != _generation) return;
    emit(ConsentState(userId: userId, loading: userId != null));
    if (userId == null) return;
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
    // Every account/session requires its own authoritative response.
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
      final analyticsAuthorized =
          _pauses.isEmpty &&
          !state.saveFailed &&
          !state.requiresReconfirmation &&
          analyticsConsent != null &&
          analyticsConsent.granted &&
          analyticsConsent.currentNotice?.version ==
              analyticsConsent.noticeVersion;
      if (analyticsAuthorized) {
        _analytics.authorize(
          userId,
          observedAt.add(Duration(seconds: response.maxAgeSeconds)),
          () =>
              !isClosed &&
              _foreground &&
              generation == _generation &&
              _userId == userId &&
              _pauses.isEmpty &&
              !state.saving &&
              !state.saveFailed &&
              !state.requiresReconfirmation,
        );
      } else {
        unawaited(_analytics.reset());
      }
      emit(
        ConsentState(
          userId: userId,
          consents: response.consents,
          analyticsAuthorized: analyticsAuthorized,
          error: state.saveFailed ? ConsentErrorKind.save : null,
          saveFailed: state.saveFailed,
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
          saveFailed: state.saveFailed,
          requiresReconfirmation: state.requiresReconfirmation,
          failedDecision: state.failedDecision,
        ),
      );
    }
  }

  /// A draft withdrawal or pending form pauses capture only until saved/cancelled.
  void Function() pauseAnalytics() {
    final owner = Object();
    final generation = _generation;
    _pauses.add(owner);
    unawaited(_analytics.reset());
    emit(
      ConsentState(
        userId: state.userId,
        consents: state.consents,
        loading: state.loading,
        saving: state.saving,
        error: state.error,
        saveFailed: state.saveFailed,
        requiresReconfirmation: state.requiresReconfirmation,
        failedDecision: state.failedDecision,
      ),
    );
    return () {
      if (generation != _generation || isClosed) return;
      if (!_pauses.remove(owner)) return;
      // Disposal can happen during a widget rebuild. Resume from a fresh read.
      scheduleMicrotask(() {
        if (isClosed ||
            generation != _generation ||
            state.saving ||
            _pauses.isNotEmpty) {
          return;
        }
        emit(ConsentState(userId: _userId, consents: state.consents));
        unawaited(refresh());
      });
    };
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
    unawaited(_analytics.reset());
    emit(
      ConsentState(
        userId: userId,
        consents: state.consents,
        saving: true,
        analyticsAuthorized: analyticsPurpose
            ? false
            : state.analyticsAuthorized,
      ),
    );
    try {
      if (generation != _generation || cancellation.isCancelled) return false;
      await _remote.decide(decision, cancelToken: cancellation);
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
            saveFailed: true,
            failedDecision: decision,
          ),
        );
      }
      return state.error == null;
    } catch (error) {
      if (generation != _generation || isClosed) return false;
      unawaited(_analytics.reset());
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
          saveFailed: !conflict,
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
