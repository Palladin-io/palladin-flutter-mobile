import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

export 'auth_event.dart';
export 'auth_state.dart';

/// BLoC responsible for managing the app-wide authentication state.
///
/// Emits [AuthAuthenticated] on successful login/check, and
/// [AuthUnauthenticated] after logout or when no stored session exists.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.authRepository}) : super(const AuthInitial()) {
    on<AuthLoginWithGoogle>(_onLoginWithGoogle);
    on<AuthRefreshRequested>(_onRefreshRequested);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthCheckRequested>(_onCheck);
  }

  final AuthRepository authRepository;

  Future<void> _onLoginWithGoogle(
    AuthLoginWithGoogle event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final result = await authRepository.loginWithGoogle();
      emit(AuthAuthenticated(
        userId: result.userId,
        isOnboarded: result.isOnboarded,
      ));
    } on AuthCancelledException {
      // User cancelled — return to unauthenticated without error
      emit(const AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onRefreshRequested(
    AuthRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      final result = await authRepository.refreshToken();
      emit(AuthAuthenticated(
        userId: result.userId,
        isOnboarded: result.isOnboarded,
      ));
    } catch (_) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await authRepository.logout();
    } catch (_) {
      // Best-effort — always emit unauthenticated
    }
    emit(const AuthUnauthenticated());
  }

  Future<void> _onCheck(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final authenticated = await authRepository.isAuthenticated();
    if (!authenticated) {
      emit(const AuthUnauthenticated());
      return;
    }

    final userId = await authRepository.getUserId();
    final isOnboarded = await authRepository.isOnboarded();

    if (userId != null) {
      emit(AuthAuthenticated(userId: userId, isOnboarded: isOnboarded));
    } else {
      emit(const AuthUnauthenticated());
    }
  }
}
