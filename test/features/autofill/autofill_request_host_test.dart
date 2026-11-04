import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_request_host.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_session_authority_provider.dart';

class _Auth extends Mock implements AuthBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/request-host');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await getIt.reset();
  });
  testWidgets(
    'cold locked request binds before unlock and opens one picker afterward',
    (tester) async {
      final states = StreamController<AuthState>.broadcast();
      final auth = _Auth();
      AuthState state = const AuthAuthenticated(userId: 'p', isOnboarded: true);
      when(() => auth.state).thenAnswer((_) => state);
      when(() => auth.stream).thenAnswer((_) => states.stream);
      var binds = 0;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'beginSourceSession' => 1,
          'pending' => {
            'id': 'request',
            'mode': 'WEB',
            'verifiedHosts': ['example.com'],
            'usernameOnly': false,
            'remainingMs': 30000,
          },
          'bind' => 'bind-${++binds}',
          _ => null,
        },
      );
      const claims = MemberSyncSessionAuthority(
        principalId: 'p',
        organizationId: 'o',
        organizationMembershipGeneration: '1',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
      );
      final source = AutoFillSourceAccessService(channel: channel);
      await source.begin(
        authority: claims,
        profileBinding: 'a' * 64,
        accountUnlock: const {},
      );
      final requests = AutoFillRequestController(
        source: source,
        channel: channel,
        authority: MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => claims,
          sessionRevision: () => 0,
        ),
      );
      getIt.registerSingleton<AuthBloc>(auth);
      getIt.registerSingleton<AutoFillSourceAccessService>(source);
      getIt.registerSingleton<AutoFillRequestController>(requests);
      getIt.registerSingleton<MemberSyncSessionAuthorityProvider>(
        MemberSyncSessionAuthorityProvider.independent(
          readClaims: () async => claims,
          sessionRevision: () => 0,
        ),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => AutoFillRequestHost(
            navigatorKey: navigator,
            prepare: () => throw StateError('unused'),
            requestPageBuilder: (_) => const Scaffold(body: Text('Picker')),
            child: child!,
          ),
          home: const Scaffold(body: Text('Locked')),
        ),
      );
      await tester.pumpAndSettle();
      expect(binds, 1);
      expect(find.text('Picker'), findsNothing);
      state = AuthAuthenticated(
        userId: 'p',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List(32),
      );
      states.add(state);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsOneWidget);
      expect(binds, 1);
      states.add(state);
      await tester.pumpAndSettle();
      expect(find.text('Picker'), findsOneWidget);
      expect(binds, 1);
      await tester.pumpWidget(const SizedBox());
      requests.dispose();
      await states.close();
    },
  );
}
