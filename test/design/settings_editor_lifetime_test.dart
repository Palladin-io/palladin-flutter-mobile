import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/permissions.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/settings/presentation/widgets/push_settings_editor.dart';
import '../../design/mobile/bootstrap.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _Owner extends Cubit<int> {
  _Owner() : super(0);
}

void main() {
  for (final permission in [
    Permissions.organizationManagement,
    Permissions.addUser,
  ]) {
    for (final cause in ['permission', 'lock', 'owner']) {
      testWidgets('root editor closes on $cause with permission $permission', (
        tester,
      ) async {
        final auth = _Auth();
        final states = StreamController<AuthState>();
        final session = demoSession().copyWith(permissions: permission);
        whenListen(auth, states.stream, initialState: session);
        final owner = _Owner();
        addTearDown(states.close);
        addTearDown(() async {
          if (!owner.isClosed) await owner.close();
        });
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => pushSettingsEditor(
                      context: context,
                      permission: permission,
                      owner: owner,
                      builder: (_) =>
                          const Scaffold(body: Text('Editor draft')),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(find.text('Editor draft'), findsOneWidget);
        if (cause == 'owner') {
          await owner.close();
        } else {
          states.add(
            cause == 'lock'
                ? session.copyWith(isVaultLocked: true)
                : session.copyWith(permissions: 0),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Editor draft'), findsNothing);
        expect(find.text('Edit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
