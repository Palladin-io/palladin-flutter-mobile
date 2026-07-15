import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/hibp_service.dart';

typedef PasswordBreachChecker = Future<HibpResult> Function(String password);

class PasswordSecurityState {
  const PasswordSecurityState({
    this.result = HibpResult.unknown,
    this.isChecking = false,
  });

  final HibpResult result;
  final bool isChecking;

  bool get blocksSubmission => isChecking || result == HibpResult.pwned;
}

/// Owns the shared, debounced HIBP state used by every master-password form.
/// The password is passed directly to the checker and is never stored in state.
class PasswordSecurityCubit extends Cubit<PasswordSecurityState> {
  PasswordSecurityCubit({
    required PasswordBreachChecker check,
    this.debounce = const Duration(milliseconds: 500),
  }) : _check = check,
       super(const PasswordSecurityState());

  final PasswordBreachChecker _check;
  final Duration debounce;

  Timer? _timer;
  var _generation = 0;

  void checkPassword(String password) {
    _timer?.cancel();
    final generation = ++_generation;

    if (password.length < 8) {
      emit(const PasswordSecurityState());
      return;
    }

    emit(const PasswordSecurityState(isChecking: true));
    _timer = Timer(debounce, () => _runCheck(password, generation));
  }

  Future<void> _runCheck(String password, int generation) async {
    var result = HibpResult.unknown;
    try {
      result = await _check(password);
    } catch (_) {
      // A network failure is represented as unavailable feedback. Passwords
      // and provider exception details must never enter logs or analytics.
    }
    if (isClosed || generation != _generation) return;
    emit(PasswordSecurityState(result: result));
  }

  @override
  Future<void> close() {
    _generation += 1;
    _timer?.cancel();
    return super.close();
  }
}
