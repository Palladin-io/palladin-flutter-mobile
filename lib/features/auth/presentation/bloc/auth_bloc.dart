import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
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
    AppLogger.d('AuthBloc', 'LoginWithGoogle started');
    emit(const AuthLoading());
    try {
      final result = await authRepository.loginWithGoogle();
      AppLogger.i('AuthBloc', 'Authenticated: userId=${result.userId}');
      emit(AuthAuthenticated(
        userId: result.userId,
        isOnboarded: result.isOnboarded,
      ));
    } on AuthCancelledException {
      AppLogger.i('AuthBloc', 'Sign-in cancelled, returning unauthenticated');
      emit(const AuthUnauthenticated());
    } catch (e) {
      AppLogger.w('AuthBloc', 'Auth error: ${e.runtimeType}');
      emit(AuthError(e));
    }
  }

  Future<void> _onRefreshRequested(
    AuthRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    AppLogger.d('AuthBloc', 'Token refresh requested');
    try {
      final result = await authRepository.refreshToken();
      AppLogger.i('AuthBloc', 'Refresh successful: userId=${result.userId}');
      emit(AuthAuthenticated(
        userId: result.userId,
        isOnboarded: result.isOnboarded,
      ));
    } catch (e) {
      AppLogger.w('AuthBloc', 'Refresh failed: ${e.runtimeType}');
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    AppLogger.d('AuthBloc', 'Logout requested');
    emit(const AuthLoading());
    try {
      await authRepository.logout();
    } catch (e) {
      AppLogger.w('AuthBloc', 'Logout error (best-effort): ${e.runtimeType}');
    }
    AppLogger.i('AuthBloc', 'Logout complete');
    emit(const AuthUnauthenticated());
  }

  Future<void> _onCheck(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    AppLogger.d('AuthBloc', 'Checking stored auth state');
    final authenticated = await authRepository.isAuthenticated();
    if (!authenticated) {
      AppLogger.i('AuthBloc', 'No stored session, unauthenticated');
      emit(const AuthUnauthenticated());
      return;
    }

    final userId = await authRepository.getUserId();
    final isOnboarded = await authRepository.isOnboarded();

    if (userId != null) {
      AppLogger.i('AuthBloc', 'Restored session: userId=$userId');
      emit(AuthAuthenticated(userId: userId, isOnboarded: isOnboarded));
    } else {
      AppLogger.w('AuthBloc', 'Token present but no userId, unauthenticated');
      emit(const AuthUnauthenticated());
    }
  }
}
