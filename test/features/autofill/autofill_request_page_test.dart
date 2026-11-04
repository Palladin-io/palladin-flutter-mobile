import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_credential_source.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_controller.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_request_session.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_source_access_service.dart';
import 'package:mobile_palladin/features/autofill/presentation/autofill_request_page.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'support/credential_source_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/request-page');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() => registerFallbackValue(Uint8List(32)));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final invalidation in [
    null,
    'sourceChanged',
    'invalidated',
    'expired',
    'prepareChanged',
  ]) {
    testWidgets(
      '$invalidation authorized picker reads metadata and reveals only explicit selection',
      (tester) async {
        Map? completed;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'complete') completed = call.arguments as Map;
          return switch (call.method) {
            'beginSourceSession' => 1,
            'pending' => {
              'id': 'request',
              'mode': 'WEB',
              'verifiedHosts': ['example.com'],
              'usernameOnly': false,
              'remainingMs': 30000,
            },
            'bind' => 'bound',
            'authenticatePresence' => 'auth',
            'validate' => true,
            'complete' => true,
            _ => null,
          };
        });
        final access = AutoFillSourceAccessService(channel: channel);
        await access.begin(
          authority: const MemberSyncSessionAuthority(
            principalId: 'p',
            organizationId: 'o',
            organizationMembershipGeneration: '1',
            offlinePolicy: '24h',
            offlinePolicyVersion: 1,
          ),
          profileBinding: 'a' * 64,
          accountUnlock: const {},
        );
        final controller = AutoFillRequestController(
          source: access,
          channel: channel,
        );
        await controller.poll();
        await controller.bind(
          principalId: 'p',
          organizationId: 'o',
          sessionId: (await access.ticket()).sessionId,
        );
        await controller.authenticatePresence();
        final entries = TestAutoFillEntries();
        final index = TestAutoFillIndex()
          ..values = [syntheticAutoFillEntry('chosen', domain: 'example.com')];
        final credentials = AutoFillCredentialSource(
          memberIndex: index,
          localEntries: entries,
        );
        final reveal = syntheticAutoFillReveal();
        when(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer((_) async => reveal);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AutoFillRequestPage(
              controller: controller,
              credentials: credentials,
              access: access,
              prepare: () async {
                if (invalidation == 'prepareChanged') {
                  await messenger.handlePlatformMessage(
                    channel.name,
                    const StandardMethodCodec().encodeMethodCall(
                      const MethodCall('sourceChanged', 'request'),
                    ),
                    (_) {},
                  );
                }
                return AutoFillRequestSession(
                  privateKey: Uint8List(32),
                  vaultIds: ['vault'],
                  validateCurrent: () {},
                );
              },
              authorizePassword: (_) async {},
              biometricAvailable: () async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        verifyNever(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        );
        expect(find.text('example.com'), findsOneWidget);
        if (invalidation != null && invalidation != 'prepareChanged') {
          if (invalidation == 'expired') {
            await tester.pump(const Duration(seconds: 31));
          } else {
            await messenger.handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(invalidation, 'request'),
              ),
              (_) {},
            );
          }
          await tester.pumpAndSettle();
          expect(find.text('example.com'), findsNothing);
          verifyZeroInteractions(entries);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          return;
        }
        await tester.tap(find.text('example.com'));
        await tester.pumpAndSettle();
        verify(
          () => entries.revealCurrentWithAuthority(
            vaultId: 'vault',
            entryId: 'chosen',
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).called(1);
        expect(completed?['sourceEpoch'], 1);
        expect(reveal.snapshot.payload, isEmpty);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
