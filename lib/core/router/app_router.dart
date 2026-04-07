import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';

/// Temporary home page displayed after successful authentication.
///
/// Will be replaced by the real vault/dashboard feature shell.
class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF000B2E),
      appBar: AppBar(
        title: Text(l10n.appTitle),
        backgroundColor: const Color(0xFF1a2a4a),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
          ),
        ],
      ),
      body: Center(
        child: Text(
          l10n.welcomeMessage,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}

/// Creates the app-level [GoRouter] with auth-aware redirects.
///
/// Unauthenticated users are redirected to `/login`. Authenticated
/// users on `/login` are redirected to `/`.
GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthBlocListenable(authBloc),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isOnLoginPage = state.matchedLocation == '/login';

      final isAuthenticated = authState is AuthAuthenticated;

      if (!isAuthenticated && !isOnLoginPage) {
        return '/login';
      }
      if (isAuthenticated && isOnLoginPage) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/',
        builder: (_, _) => const _PlaceholderHomePage(),
      ),
    ],
  );
}

/// Bridges [AuthBloc] stream to [ChangeNotifier] so that [GoRouter]
/// can react to auth state changes and re-evaluate redirects.
class _AuthBlocListenable extends ChangeNotifier {
  _AuthBlocListenable(AuthBloc bloc) {
    _subscription = bloc.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
