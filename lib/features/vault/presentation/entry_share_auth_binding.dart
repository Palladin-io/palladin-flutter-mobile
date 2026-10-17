import '../../auth/presentation/bloc/auth_bloc.dart';

Object? entryShareAuthBinding(AuthState state) => switch (state) {
  AuthAuthenticated() => (
    state.userId,
    state.isVaultLocked,
    state.isOnboarded,
    state.emailVerified,
    state.permissions,
    state.privateKey,
  ),
  AuthUnauthenticated() => AuthUnauthenticated,
  _ => null,
};
