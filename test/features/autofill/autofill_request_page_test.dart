import 'package:flutter/material.dart';
import 'package:mobile_palladin/core/widgets/warning_zone.dart';
import 'package:mobile_palladin/core/widgets/sheet_action_buttons.dart';
import 'package:mobile_palladin/core/widgets/app_empty_state.dart';
import 'package:mobile_palladin/core/widgets/list_screen_header.dart';
import 'package:mobile_palladin/core/widgets/app_search_field.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_list_card.dart';
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
    'readChanged',
    'unauthorizedChanged',
    'empty',
    'manualWeb',
    'manualWebRevoke',
    'manualWebReplaced',
    'manualWebSourceChanged',
    'manualWebDoubleTap',
    'manualWebCancel',
    'manualNative',
    'usernameOnly',
  ]) {
    for (final locale in [
      'en',
      if (invalidation == null ||
          invalidation == 'empty' ||
          invalidation == 'manualWeb' ||
          invalidation == 'manualNative' ||
          invalidation == 'usernameOnly')
        'pl',
    ]) {
      testWidgets(
        '$locale $invalidation authorized picker reads metadata and reveals only explicit selection',
        (tester) async {
          final manualWeb = invalidation?.startsWith('manualWeb') ?? false;
          final manualNative = invalidation == 'manualNative';
          final usernameOnly = invalidation == 'usernameOnly';
          final needsConsent = manualWeb || manualNative || usernameOnly;
          var consentCalls = 0;
          var requestId = 'request';
          late AutoFillRequestController controller;
          Map? completed;
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'complete') completed = call.arguments as Map;
            if (call.method == 'confirmSelection') {
              consentCalls++;
              if (invalidation == 'manualWebReplaced') {
                await messenger.handlePlatformMessage(
                  channel.name,
                  const StandardMethodCodec().encodeMethodCall(
                    const MethodCall('invalidated', 'request'),
                  ),
                  (_) {},
                );
                requestId = 'replacement';
                await controller.poll();
              }
              if (invalidation == 'manualWebRevoke' ||
                  invalidation == 'manualWebSourceChanged') {
                await messenger.handlePlatformMessage(
                  channel.name,
                  const StandardMethodCodec().encodeMethodCall(
                    MethodCall(
                      invalidation == 'manualWebSourceChanged'
                          ? 'sourceChanged'
                          : 'invalidated',
                      'request',
                    ),
                  ),
                  (_) {},
                );
              }
            }
            return switch (call.method) {
              'beginSourceSession' => 1,
              'pending' => {
                'id': requestId,
                'mode': manualWeb
                    ? 'MANUAL_WEB'
                    : manualNative
                    ? 'MANUAL_NATIVE'
                    : 'WEB',
                'verifiedHosts': manualWeb || manualNative
                    ? []
                    : ['example.com'],
                if (manualWeb) 'reportedHost': 'example.com',
                if (manualWeb) 'destinationApp': 'Test App (example.app)',
                'usernameOnly': usernameOnly,
                'remainingMs': 30000,
              },
              'bind' => 'bound',
              'authenticatePresence' => 'auth',
              'confirmSelection' => 'one-use-consent',
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
          controller = AutoFillRequestController(
            source: access,
            channel: channel,
          );
          await controller.poll();
          await controller.bind(
            principalId: 'p',
            organizationId: 'o',
            sessionId: (await access.ticket()).sessionId,
          );
          if (invalidation != 'unauthorizedChanged') {
            await controller.authenticatePresence();
          }
          final entries = TestAutoFillEntries();
          final index = TestAutoFillIndex()
            ..values = invalidation == 'empty'
                ? []
                : [
                    syntheticAutoFillEntry('chosen', domain: 'example.com'),
                    if (!manualNative)
                      syntheticAutoFillEntry(
                        'unrelated',
                        domain: 'other.example',
                      ),
                  ];
          var reads = 0;
          index.waiting = () async {
            reads++;
            if (invalidation == 'readChanged' && reads == 1) {
              for (var change = 0; change < 2; change++) {
                await messenger.handlePlatformMessage(
                  channel.name,
                  const StandardMethodCodec().encodeMethodCall(
                    const MethodCall('sourceChanged', 'request'),
                  ),
                  (_) {},
                );
              }
            }
          };
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
              locale: Locale(locale),
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
          if (invalidation == 'unauthorizedChanged') {
            await messenger.handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('sourceChanged', 'request'),
              ),
              (_) {},
            );
            await tester.pumpAndSettle();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(AutoFillRequestPage)),
            )!;
            expect(find.text(l10n.autofillRequestFailed), findsNothing);
            expect(find.byType(EntryListCard), findsNothing);
            verifyZeroInteractions(entries);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            return;
          }
          verifyNever(
            () => entries.revealCurrentWithAuthority(
              vaultId: 'vault',
              entryId: 'chosen',
              memberPrivateKey: any(named: 'memberPrivateKey'),
            ),
          );
          if (invalidation == 'empty') {
            final empty = tester.widget<AppEmptyState>(
              find.byType(AppEmptyState),
            );
            expect(
              empty.title,
              AppLocalizations.of(
                tester.element(find.byType(AutoFillRequestPage)),
              )!.autofillRequestEmpty,
            );
            expect(empty.onAction, isNull);
            verifyZeroInteractions(entries);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            return;
          }
          expect(find.text('account-chosen'), findsOneWidget);
          expect(find.byType(AppBar), findsNothing);
          final header = tester.widget<ListScreenHeader>(
            find.byType(ListScreenHeader),
          );
          expect(
            header.title,
            AppLocalizations.of(
              tester.element(find.byType(AutoFillRequestPage)),
            )!.vaultTabEntries,
          );
          expect(find.byType(EntryListCard), findsOneWidget);
          final search = tester.widget<AppSearchField>(
            find.byType(AppSearchField),
          );
          expect(search.controller.text, manualNative ? '' : 'example.com');
          await tester.enterText(find.byType(TextField), 'not-found');
          await tester.pumpAndSettle();
          expect(find.byType(EntryListCard), findsNothing);
          final empty = tester.widget<AppEmptyState>(
            find.byType(AppEmptyState),
          );
          expect(
            empty.title,
            AppLocalizations.of(
              tester.element(find.byType(AutoFillRequestPage)),
            )!.searchResultsEmpty,
          );
          expect(empty.onAction, isNotNull);
          empty.onAction!();
          await tester.pumpAndSettle();
          expect(search.controller.text, isEmpty);
          expect(find.byType(EntryListCard), findsOneWidget);
          verifyZeroInteractions(entries);
          await tester.enterText(find.byType(TextField), 'chosen');
          await tester.pumpAndSettle();
          expect(find.byType(EntryListCard), findsOneWidget);
          if (invalidation != null &&
              !needsConsent &&
              invalidation != 'prepareChanged' &&
              invalidation != 'readChanged') {
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
            if (invalidation == 'sourceChanged') {
              expect(find.byType(EntryListCard), findsOneWidget);
              expect(reads, 2);
              await messenger.handlePlatformMessage(
                channel.name,
                const StandardMethodCodec().encodeMethodCall(
                  const MethodCall('sourceChanged', 'request'),
                ),
                (_) {},
              );
              await tester.pumpAndSettle();
              expect(reads, 2); // At most one automatic recovery per request.
            }
            expect(find.byType(EntryListCard), findsNothing);
            verifyZeroInteractions(entries);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            return;
          }
          if (invalidation == 'readChanged') expect(reads, 2);
          if (manualWeb) {
            expect(
              find.textContaining('Test App (example.app)'),
              findsOneWidget,
            );
          }
          final l10n = AppLocalizations.of(
            tester.element(find.byType(AutoFillRequestPage)),
          )!;
          expect(consentCalls, 0);
          expect(completed, isNull);
          expect(find.byType(SheetActionButtons), findsNothing);
          expect(
            find.byType(WarningZone),
            needsConsent ? findsOneWidget : findsNothing,
          );
          if (manualNative) {
            expect(
              find.text(l10n.autofillRequestManualWarning),
              findsOneWidget,
            );
          }
          if (invalidation == 'manualWebCancel') {
            await tester.tap(find.byTooltip(l10n.vaultCancel));
            await tester.pumpAndSettle();
            expect(consentCalls, 0);
            expect(completed, isNull);
            verifyZeroInteractions(entries);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            return;
          }
          await tester.tap(find.text('example.com'));
          if (invalidation == 'manualWebDoubleTap') {
            await tester.tap(find.text('example.com'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(BottomSheet), findsNothing);
          expect(consentCalls, needsConsent ? 1 : 0);
          if (invalidation == 'manualWebRevoke' ||
              invalidation == 'manualWebReplaced' ||
              invalidation == 'manualWebSourceChanged') {
            expect(completed, isNull);
            verifyZeroInteractions(entries);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            return;
          }
          if (needsConsent) {
            expect(completed?['consentToken'], 'one-use-consent');
          }
          if (usernameOnly) expect(completed!.containsKey('password'), isFalse);
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
}
