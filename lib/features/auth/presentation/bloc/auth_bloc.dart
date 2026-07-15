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
    on<VaultUnlocked>(_onVaultUnlocked);
    on<VaultLockRequested>(_onVaultLockRequested);
    on<OnboardingCompleted>(_onOnboardingCompleted);
    on<PasswordSessionEstablished>(_onPasswordSessionEstablished);
    on<AuthEmailVerified>(_onEmailVerified);
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
      final permissions = await authRepository.getPermissions();
      final email = await authRepository.getEmail();
      final emailVerified = await authRepository.isEmailVerified();
      final authProvider = await authRepository.getAuthProvider();
      AppLogger.i('AuthBloc', 'Authenticated: userId=${result.userId}');
      emit(
        AuthAuthenticated(
          userId: result.userId,
          isOnboarded: result.isOnboarded,
          permissions: permissions,
          email: email,
          emailVerified: emailVerified,
          authProvider: authProvider,
        ),
      );
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
      await authRepository.refreshToken();
      final userId = await authRepository.getUserId();
      final isOnboarded = await authRepository.isOnboarded();
      final permissions = await authRepository.getPermissions();
      final email = await authRepository.getEmail();
      final emailVerified = await authRepository.isEmailVerified();
      final authProvider = await authRepository.getAuthProvider();
      if (userId == null) {
        AppLogger.w('AuthBloc', 'Refresh succeeded without a stored userId');
        emit(const AuthUnauthenticated());
        return;
      }
      AppLogger.i('AuthBloc', 'Refresh successful: userId=$userId');
      emit(
        AuthAuthenticated(
          userId: userId,
          isOnboarded: isOnboarded,
          permissions: permissions,
          email: email,
          emailVerified: emailVerified,
          authProvider: authProvider,
        ),
      );
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
    final stateBeforeLogout = state;
    emit(const AuthLoading());
    try {
      await authRepository.logout();
    } catch (e) {
      // Security-critical local revocation/storage cleanup failed. We cannot
      // claim the session ended until AutoFill access, tokens, and the
      // biometric key are reliably unavailable; remote failures are swallowed
      // by the repository before they reach this branch.
      AppLogger.w('AuthBloc', 'Logout aborted: ${e.runtimeType}');
      emit(stateBeforeLogout);
      return;
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
    final permissions = await authRepository.getPermissions();
    final email = await authRepository.getEmail();
    final emailVerified = await authRepository.isEmailVerified();
    final authProvider = await authRepository.getAuthProvider();

    if (userId != null) {
      AppLogger.i('AuthBloc', 'Restored session: userId=$userId');
      emit(
        AuthAuthenticated(
          userId: userId,
          isOnboarded: isOnboarded,
          permissions: permissions,
          email: email,
          emailVerified: emailVerified,
          authProvider: authProvider,
        ),
      );
    } else {
      AppLogger.w('AuthBloc', 'Token present but no userId, unauthenticated');
      emit(const AuthUnauthenticated());
    }
  }

  /// Handles a successful master-password (or biometric) unlock by
  /// carrying the derived keys into the existing [AuthAuthenticated]
  /// state. No-op if the user is no longer authenticated (e.g. logged
  /// out mid-unlock).
  void _onVaultUnlocked(VaultUnlocked event, Emitter<AuthState> emit) {
    final current = state;
    if (current is! AuthAuthenticated) {
      AppLogger.w('AuthBloc', 'VaultUnlocked ignored — not authenticated');
      return;
    }
    AppLogger.i('AuthBloc', 'Vault unlocked for userId=${current.userId}');
    emit(
      current.copyWith(
        isVaultLocked: false,
        masterKey: event.masterKey,
        privateKey: event.privateKey,
      ),
    );
  }

  /// Locks the vault by clearing the in-memory key material. Keeps the
  /// user authenticated so the unlock screen stays scoped to the
  /// current session.
  void _onVaultLockRequested(
    VaultLockRequested event,
    Emitter<AuthState> emit,
  ) {
    final current = state;
    if (current is! AuthAuthenticated) return;
    AppLogger.i('AuthBloc', 'Vault lock requested');
    emit(current.copyWith(isVaultLocked: true, clearKeys: true));
  }

  /// Called when the onboarding wizard finishes setup.
  ///
  /// When the event carries the freshly derived [masterKey] and
  /// [privateKey] (fresh setup), the vault is marked unlocked and the
  /// keys are carried into [AuthAuthenticated] — exactly the state a
  /// successful unlock produces, so no need to re-enter the master
  /// password that was just set. If the keys are absent (the "already
  /// onboarded" 409 path), the vault stays locked so the router forwards
  /// to `/unlock` — never leave an "unlocked" state with null keys.
  Future<void> _onOnboardingCompleted(
    OnboardingCompleted event,
    Emitter<AuthState> emit,
  ) async {
    final userId = await authRepository.getUserId();
    if (userId == null) {
      AppLogger.w('AuthBloc', 'OnboardingCompleted — no userId in storage');
      emit(const AuthUnauthenticated());
      return;
    }
    final permissions = await authRepository.getPermissions();
    final email = await authRepository.getEmail();
    final emailVerified = await authRepository.isEmailVerified();
    final authProvider = await authRepository.getAuthProvider();
    final hasKeys = event.masterKey != null && event.privateKey != null;
    AppLogger.i(
      'AuthBloc',
      'Onboarding completed for userId=$userId (vaultUnlocked=$hasKeys)',
    );
    emit(
      AuthAuthenticated(
        userId: userId,
        isOnboarded: true,
        isVaultLocked: !hasKeys,
        masterKey: event.masterKey,
        privateKey: event.privateKey,
        permissions: permissions,
        email: email,
        emailVerified: emailVerified,
        authProvider: authProvider,
      ),
    );
  }

  /// Handles a completed email + master-password authentication. The
  /// flow's cubit has already persisted the tokens, so read the
  /// session metadata from storage and carry the freshly derived keys
  /// into an unlocked session. A password account whose email is not yet
  /// verified is still marked unlocked here — the router shows the
  /// verification gate ahead of the vault based on [emailVerified].
  Future<void> _onPasswordSessionEstablished(
    PasswordSessionEstablished event,
    Emitter<AuthState> emit,
  ) async {
    final userId = await authRepository.getUserId();
    if (userId == null) {
      AppLogger.w('AuthBloc', 'PasswordSession — no userId in storage');
      emit(const AuthUnauthenticated());
      return;
    }
    final permissions = await authRepository.getPermissions();
    final email = await authRepository.getEmail();
    final emailVerified = await authRepository.isEmailVerified();
    final authProvider = await authRepository.getAuthProvider();
    AppLogger.i(
      'AuthBloc',
      'Password session established for userId=$userId '
          '(emailVerified=$emailVerified)',
    );
    emit(
      AuthAuthenticated(
        userId: userId,
        isOnboarded: true,
        isVaultLocked: false,
        masterKey: event.masterKey,
        privateKey: event.privateKey,
        permissions: permissions,
        email: email,
        emailVerified: emailVerified,
        authProvider: authProvider,
      ),
    );
  }

  /// Flips the current session to verified after the user confirms their
  /// email. Best-effort refreshes the token so the `email_verified` claim
  /// propagates to future API calls, then re-emits the authenticated
  /// state with the keys preserved (a same-session verification stays
  /// unlocked). No-op when not authenticated.
  Future<void> _onEmailVerified(
    AuthEmailVerified event,
    Emitter<AuthState> emit,
  ) async {
    final current = state;
    if (current is! AuthAuthenticated) {
      AppLogger.w('AuthBloc', 'EmailVerified ignored — not authenticated');
      return;
    }
    try {
      final claimAlreadyUpdated = await authRepository.isEmailVerified();
      if (!claimAlreadyUpdated) {
        await authRepository.refreshToken();
      }
    } catch (e) {
      // The verification already succeeded server-side; a failed refresh
      // only means the local token still carries the stale claim until the
      // next refresh. Proceed optimistically so the user is not stuck.
      AppLogger.w('AuthBloc', 'Post-verify refresh failed: ${e.runtimeType}');
    }
    AppLogger.i('AuthBloc', 'Email verified for userId=${current.userId}');
    emit(current.copyWith(emailVerified: true));
  }
}
