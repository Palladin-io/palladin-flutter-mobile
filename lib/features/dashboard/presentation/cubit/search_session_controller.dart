import '../../../auth/presentation/bloc/auth_state.dart';

import 'search_cubit.dart';

/// Clears every mounted global-search view on a security transition.
final class SearchSessionController {
  Future<void>? _preparation;
  String? _principalId;

  final Set<SearchCubit> _active = {};
  final Set<void Function()> _viewClearers = {};

  /// Share Home attachment work only. Authoritative lifecycle repair bypasses
  /// this view scope and continues to synchronize the Member index normally.
  Future<void> prepare(String principalId, Future<void> Function() operation) {
    if (_principalId != principalId) {
      lock();
      _principalId = principalId;
    }
    final active = _preparation;
    if (active != null) return active;
    late final Future<void> preparation;
    preparation = Future<void>.sync(operation).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(_preparation, preparation)) _preparation = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    _preparation = preparation;
    return preparation;
  }

  static bool replacesUnlockedSession(AuthState previous, AuthState current) =>
      previous is AuthAuthenticated &&
      current is AuthAuthenticated &&
      !previous.isVaultLocked &&
      !current.isVaultLocked &&
      (previous.userId != current.userId ||
          !identical(previous.privateKey, current.privateKey));

  void replaceUnlockedSession(
    AuthAuthenticated current, {
    required void Function() invalidatePreparation,
  }) {
    lock();
    invalidatePreparation();
    final key = current.privateKey;
    if (current.isVaultLocked || key == null || key.isEmpty) return;
    _principalId = current.userId;
    for (final cubit in List<SearchCubit>.of(_active)) {
      cubit.prepare(key, principalId: current.userId);
    }
  }

  void attach(SearchCubit cubit) => _active.add(cubit);

  void detach(SearchCubit cubit) => _active.remove(cubit);

  void attachView(void Function() clear) => _viewClearers.add(clear);

  void detachView(void Function() clear) => _viewClearers.remove(clear);

  void lock() {
    _preparation = null;
    _principalId = null;
    for (final cubit in List<SearchCubit>.of(_active)) {
      cubit.securityReset();
    }
    for (final clear in List<void Function()>.of(_viewClearers)) {
      clear();
    }
  }
}
