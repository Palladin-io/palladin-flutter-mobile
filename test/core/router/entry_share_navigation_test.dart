import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_palladin/config/env_config.dart';
import 'package:mobile_palladin/core/router/app_router.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_ingress.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_link_service.dart';
import 'package:mobile_palladin/features/vault/presentation/entry_share_navigation.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_share_receiver_frame.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Auth extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.palladin.mobile/entry-sharing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final state in <AuthState>[
    const AuthInitial(),
    const AuthLoading(),
    const AuthUnauthenticated(),
    const AuthAuthenticated(
      userId: 'user-a',
      isOnboarded: false,
      emailVerified: false,
    ),
    const AuthAuthenticated(userId: 'user-a', isOnboarded: true),
    const AuthAuthenticated(
      userId: 'user-a',
      isOnboarded: true,
      isVaultLocked: false,
    ),
  ]) {
    testWidgets(
      'production public route bypasses account/vault gates for ${state.runtimeType}: $state',
      (tester) async {
        final auth = _Auth();
        whenListen(auth, const Stream<AuthState>.empty(), initialState: state);
        final router = createRouter(auth)..go(AppRoutes.entryShare);
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.toString(),
          AppRoutes.entryShare,
        );
        expect(find.byType(EntryShareReceiverPlaceholder), findsOneWidget);
        router.go('/share?unexpected=synthetic#untrusted-fragment');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.toString(),
          AppRoutes.entryShare,
        );
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await auth.close();
      },
    );
  }

  group('native navigation', () {
    late EntryShareIngress ingress;
    late EntryShareNavigation navigation;
    late GoRouter router;
    late List<Uri> locations;
    late DateTime now;
    Map<String, Object?>? reply;
    var generation = 0;
    final fragment = '#v=1&key=${'A' * 42}E&access=${'A' * 42}I';
    const id = '00112233-4455-4677-8899-aabbccddeeff';
    setUp(() {
      now = DateTime.utc(2026, 9, 21);
      reply = null;
      generation = 0;
      locations = [];
      messenger.setMockMethodCallHandler(channel, (_) async {
        final value = reply;
        reply = null;
        return value;
      });
      ingress = EntryShareIngress(
        links: EntryShareLinkService(
          EnvConfig.staging(sharingWebOrigin: 'https://stage.palladin.io'),
        ),
        now: () => now,
      );
      router = GoRouter(
        initialLocation: '/other',
        routes: [
          GoRoute(
            path: '/other',
            builder: (_, _) => const Scaffold(body: Text('Other')),
          ),
          GoRoute(
            path: AppRoutes.entryShare,
            builder: (_, _) => const EntryShareReceiverPlaceholder(),
          ),
        ],
      );
      router.routeInformationProvider.addListener(
        () => locations.add(router.routeInformationProvider.value.uri),
      );
      navigation = EntryShareNavigation(ingress, router);
    });
    tearDown(() {
      navigation.dispose();
      ingress.dispose();
      router.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    Future<void> mount(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      navigation.start();
      unawaited(ingress.start());
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();
    }

    void link({String? url}) {
      reply = {
        'generation': ++generation,
        'url': url ?? 'https://stage.palladin.io/share/$id$fragment',
        'receivedAtUnixMs': now.millisecondsSinceEpoch,
        'ageMilliseconds': 0,
      };
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('pending', generation)),
        (_) {},
      );
    }

    testWidgets(
      'cold/warm capability sends only the constant route to GoRouter',
      (tester) async {
        await mount(tester);
        link();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.toString(),
          AppRoutes.entryShare,
        );
        expect(locations, isNotEmpty);
        for (final uri in locations) {
          expect(uri.hasQuery || uri.hasFragment, false);
          expect(uri.toString(), isNot(contains(id)));
          expect(uri.toString(), isNot(contains('key=')));
        }
        final count = locations.length;
        link();
        await tester.pumpAndSettle();
        expect(locations.length, count);
        ingress.clear();
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'background link waits for foreground without a route or receipt',
      (tester) async {
        await mount(tester);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        link();
        await tester.pump();
        await tester.pump();
        expect(router.routeInformationProvider.value.uri.path, '/other');
        expect(ingress.hasPending, true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.entryShare,
        );
        ingress.clear();
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets('invalid origin cannot navigate or retain the previous link', (
      tester,
    ) async {
      await mount(tester);
      link(url: 'https://evil.example.test/share/$id$fragment');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/other');
      expect(ingress.hasPending, false);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'disposal before pending callback prevents delayed navigation',
      (tester) async {
        await mount(tester);
        link();
        navigation.dispose();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/other');
        ingress.clear();
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'detach clears pending ingress and does not resurrect on resume',
      (tester) async {
        await mount(tester);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        link();
        await tester.pump();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.detached,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(ingress.hasPending, false);
        expect(router.routeInformationProvider.value.uri.path, '/other');
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
