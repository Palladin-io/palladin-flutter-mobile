import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/biometric_key_store.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

enum BiometricSetupStatus { unavailable, available, enabled }

class BiometricSetupState {
  const BiometricSetupState({
    this.status = BiometricSetupStatus.unavailable,
    this.dismissed = false,
    this.busy = false,
    this.failed = false,
  });
  final BiometricSetupStatus status;
  final bool dismissed;
  final bool busy;
  final bool failed;
}

/// Enrollment is requested only by an explicit setup action, after login.
class BiometricSetupCubit extends Cubit<BiometricSetupState> {
  BiometricSetupCubit({
    required BiometricKeyStore keyStore,
    required SharedPreferences preferences,
    required AuthState Function() currentAuth,
  }) : _keys = keyStore,
       _preferences = preferences,
       _currentAuth = currentAuth,
       super(const BiometricSetupState());
  final BiometricKeyStore _keys;
  final SharedPreferences _preferences;
  final AuthState Function() _currentAuth;
  String _dismissKey(String userId) => 'biometric_setup_dismissed:$userId';

  Future<void> refresh() async {
    if (state.busy || isClosed) return;
    final auth = _currentAuth();
    if (auth is! AuthAuthenticated) return;
    final enrolled = await _keys.isEnrolled();
    final available = enrolled || await _keys.canStore();
    final current = _currentAuth();
    if (isClosed ||
        state.busy ||
        current is! AuthAuthenticated ||
        current.userId != auth.userId) {
      return;
    }
    emit(
      BiometricSetupState(
        status: enrolled
            ? BiometricSetupStatus.enabled
            : available
            ? BiometricSetupStatus.available
            : BiometricSetupStatus.unavailable,
        dismissed: _preferences.getBool(_dismissKey(auth.userId)) ?? false,
      ),
    );
  }

  Future<void> dismiss() async {
    final auth = _currentAuth();
    if (auth is! AuthAuthenticated || state.busy) return;
    await _preferences.setBool(_dismissKey(auth.userId), true);
    if (!isClosed) {
      emit(BiometricSetupState(status: state.status, dismissed: true));
    }
  }

  Future<void> enable(BiometricPromptCopy prompt) async {
    final auth = _currentAuth();
    if (state.busy ||
        isClosed ||
        auth is! AuthAuthenticated ||
        auth.isVaultLocked) {
      return;
    }
    final source = auth.masterKey;
    if (source == null) return;
    final generation = _keys.generation;
    final copy = Uint8List.fromList(source);
    bool valid() {
      final current = _currentAuth();
      return !isClosed &&
          _keys.generation == generation &&
          current is AuthAuthenticated &&
          !current.isVaultLocked &&
          current.userId == auth.userId &&
          identical(current.masterKey, source);
    }

    emit(
      BiometricSetupState(
        status: state.status,
        dismissed: state.dismissed,
        busy: true,
      ),
    );
    try {
      await _keys.enroll(copy, prompt, expectedGeneration: generation);
      if (!valid()) {
        // Logout already owns cleanup when it advances the generation.
        if (_keys.generation == generation) await _keys.clear();
        return;
      }
      await _preferences.setBool(_dismissKey(auth.userId), true);
      if (!valid()) {
        if (_keys.generation == generation) await _keys.clear();
        return;
      }
      emit(
        const BiometricSetupState(
          status: BiometricSetupStatus.enabled,
          dismissed: true,
        ),
      );
    } catch (error) {
      if (error is BiometricKeyCleanupException) rethrow;
      if (!valid() && _keys.generation == generation) {
        // The protected write can succeed before its enrollment marker fails.
        // A stale flow must revoke that partial copy, but never a newer one.
        await _keys.clear();
      } else if (valid()) {
        emit(
          BiometricSetupState(
            status: BiometricSetupStatus.available,
            dismissed: state.dismissed,
            failed:
                error is! BiometricAuthException ||
                error.reason != BiometricAuthFailureReason.canceled,
          ),
        );
      }
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  Future<void> disable() async {
    if (isClosed || state.busy) return;
    final auth = _currentAuth();
    if (auth is! AuthAuthenticated) return;
    emit(
      BiometricSetupState(status: state.status, dismissed: true, busy: true),
    );
    try {
      await _keys.clear();
      await _preferences.setBool(_dismissKey(auth.userId), true);
      if (!isClosed) {
        emit(
          const BiometricSetupState(
            status: BiometricSetupStatus.available,
            dismissed: true,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          const BiometricSetupState(
            status: BiometricSetupStatus.enabled,
            dismissed: true,
            failed: true,
          ),
        );
      }
    }
  }
}
