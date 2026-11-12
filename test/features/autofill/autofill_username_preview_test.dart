import 'dart:async';

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
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

import 'support/credential_source_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/username-preview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() => registerFallbackValue(Uint8List(32)));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final mode in ['bounded', 'remount', 'dispose', 'invalidated']) {
    testWidgets('legacy username previews: $mode', (tester) async {
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
          'bind' => 'bound',
          'authenticatePresence' => 'auth',
          _ => null,
        },
      );
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
      final index = TestAutoFillIndex()
        ..values = [
          for (var i = 0; i < 10; i++)
            MemberIndexEntry(
              entryId: '$i',
              entryType: 1,
              memberLabel: 'Account $i',
              searchFields: const [],
              revision: '1',
              state: MemberEntryState.active,
              autofillDomains: const ['example.com'],
            ),
        ];
      final entries = TestAutoFillEntries();
      final release = Completer<void>();
      var reads = 0, active = 0, maximum = 0;
      final reveals = <LocalCurrentEntryReveal>[];
      when(
        () => entries.revealCurrentWithAuthority(
          vaultId: 'vault',
          entryId: any(named: 'entryId'),
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((call) async {
        reads++;
        active++;
        if (active > maximum) maximum = active;
        if (mode != 'remount') await release.future;
        active--;
        final reveal = syntheticAutoFillReveal();
        reveal.snapshot.entry['id'] = call.namedArguments[#entryId];
        reveals.add(reveal);
        return reveal;
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AutoFillRequestPage(
            controller: controller,
            credentials: AutoFillCredentialSource(
              memberIndex: index,
              localEntries: entries,
            ),
            access: access,
            prepare: () async => AutoFillRequestSession(
              privateKey: Uint8List(32),
              vaultIds: ['vault'],
              validateCurrent: () {},
            ),
            authorizePassword: (_) async {},
            biometricAvailable: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (mode == 'remount') {
        final initialReads = reads;
        expect(initialReads, greaterThan(0));
        await tester.enterText(find.byType(TextField).first, 'no-match');
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'example.com');
        await tester.pumpAndSettle();
        expect(
          reads,
          initialReads,
          reason: 'Remount must reuse only the current username',
        );
      } else {
        expect(reads, 2);
        expect(maximum, 2);
        if (mode == 'dispose') await tester.pumpWidget(const SizedBox());
        if (mode == 'invalidated') {
          await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('invalidated', 'request'),
            ),
            (_) {},
          );
          await tester.pump();
        }
        release.complete();
        await tester.pumpAndSettle();
        if (mode == 'dispose' || mode == 'invalidated') expect(reads, 2);
        expect(maximum, lessThanOrEqualTo(2));
      }
      for (final reveal in reveals) {
        expect(reveal.snapshot.payload, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
