import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';

/// Root editors must not outlive the authorization or Cubit of their owner.
Future<void> pushSettingsEditor<S>({
  required BuildContext context,
  required int permission,
  required Cubit<S> owner,
  required WidgetBuilder builder,
}) async {
  final auth = context.read<AuthBloc>();
  final initial = auth.state;
  bool authorized(AuthState state) =>
      state is AuthAuthenticated &&
      initial is AuthAuthenticated &&
      state.userId == initial.userId &&
      !state.isVaultLocked &&
      (state.permissions & permission) == permission;
  if (owner.isClosed || !authorized(initial)) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = MaterialPageRoute<void>(builder: builder);
  void dismiss() {
    if (route.isActive) navigator.removeRoute(route);
  }

  final authSubscription = auth.stream.listen((state) {
    if (!authorized(state)) dismiss();
  });
  final ownerSubscription = owner.stream.listen((_) {}, onDone: dismiss);
  try {
    await navigator.push(route);
  } finally {
    await authSubscription.cancel();
    await ownerSubscription.cancel();
  }
}
