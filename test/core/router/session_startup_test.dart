import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/core/widgets/privacy_cover.dart';
import 'package:mobile_palladin/features/auth/presentation/pages/login_page.dart';
import 'package:mobile_palladin/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';

class _Repository extends Mock implements AuthRepository {}

void main() {
  testWidgets(
    'unresolved session renders the opaque brand cover, not login controls',
    (tester) async {
      final auth = AuthBloc(authRepository: _Repository());
      final router = createRouter(auth);
      addTearDown(router.dispose);
      addTearDown(auth.close);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(PrivacyCover), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final hasSession in [true, false]) {
    testWidgets(
      'startup waits for stored session before choosing ${hasSession ? 'unlock' : 'login'}',
      (tester) async {
        final session = Completer<bool>();
        final repository = _Repository();
        when(
          () => repository.isAuthenticated(),
        ).thenAnswer((_) => session.future);
        when(
          () => repository.getUserId(),
        ).thenAnswer((_) async => 'fixture-account');
        when(() => repository.isOnboarded()).thenAnswer((_) async => true);
        when(() => repository.getPermissions()).thenAnswer((_) async => 0);
        when(() => repository.getEmail()).thenAnswer((_) async => null);
        when(() => repository.isEmailVerified()).thenAnswer((_) async => true);
        when(
          () => repository.getAuthProvider(),
        ).thenAnswer((_) async => 'password');
        final auth = AuthBloc(authRepository: repository);
        final router = createRouter(auth);
        addTearDown(router.dispose);
        addTearDown(auth.close);
        late BuildContext routeContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                routeContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        Future<String> destination() async {
          final matches = await router.routeInformationParser
              .parseRouteInformationWithDependencies(
                router.routeInformationProvider.value,
                routeContext,
              );
          return matches.uri.path;
        }

        expect(await destination(), '/startup');
        auth.add(const AuthCheckRequested());
        await tester.pump(const Duration(seconds: 3));
        expect(await destination(), '/startup');
        final restored = auth.stream.first;
        session.complete(hasSession);
        await restored;
        expect(await destination(), hasSession ? '/unlock' : '/login');
        if (hasSession) {
          final state = auth.state as AuthAuthenticated;
          expect(state.isVaultLocked, isTrue);
          expect(state.masterKey, isNull);
          expect(state.privateKey, isNull);
        }
      },
    );
  }
}
