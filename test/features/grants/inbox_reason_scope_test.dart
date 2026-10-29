import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/repositories/grants_repository_impl.dart';
import 'package:mobile_palladin/features/notifications/data/services/notification_presentation_resolver.dart';
import 'package:mobile_palladin/features/notifications/domain/entities/inbox_notification.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/data/services/encrypted_reason_crypto_service.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_history_reason_resolver.dart';
import 'package:mobile_palladin/features/approval/domain/entities/encrypted_reason.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/agent_discovery_provisioning.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';

class _Remote extends Mock implements GrantsRemoteDatasource {}

class _Index extends Mock implements MemberIndexReader {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Discovery extends Mock implements AgentDiscoveryRemote {}

class _ReasonCrypto extends Mock implements EncryptedReasonCrypto {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  for (final scenario in [
    'shared',
    'slow-grant',
    'unreadable-grant',
    'forged-reason',
    'fresh-resolution',
    'overlapping-resolutions',
    'lock-during-decrypt',
    'failed-vault',
    'timed-reads',
  ]) {
    test(
      'Inbox shares encrypted reads with independent key lifetime: $scenario',
      () async {
        final messagePrivateKey = Uint8List.fromList(
          List<int>.generate(32, (index) => index + 1),
        );
        const fingerprint = 'authenticated-message-key-fingerprint';

        final reason = EncryptedReason(
          descriptor: {
            'protocolVersion': 2,
            'purpose': 'encryptedReason',
            'scope': {
              'organizationId': 'org-1',
              'vaultId': 'v-1',
              'entryId': 'e-1',
              'grantOrRequestId': 'g-1',
              'agentId': 'a-1',
              'memberId': null,
            },
            'resourceRevision': '1',
            'keyVersion': 1,
            'memberKeyGeneration': 1,
            'binding': {
              'recipientKeyVersion': 1,
              'recipientKeyFingerprint': fingerprint,
              'requestedMethods': 1,
            },
          },
          encodedSuitePayload: 'payload',
          wrappedReasonDek: const {},
          agentSignature: 'signature',
        );
        final encryptedReason = <String, dynamic>{
          'descriptor': reason.descriptor,
          'encodedSuitePayload': reason.encodedSuitePayload,
          'wrappedReasonDek': reason.wrappedReasonDek,
          'agentSignature': reason.agentSignature,
        };
        registerFallbackValue(reason);
        final grants = List.generate(
          8,
          (i) => GrantModel(
            id: 'g-$i',
            vaultId: scenario == 'failed-vault' && i == 7 ? 'v-2' : 'v-1',
            agentId: 'a-1',
            status: 'active',
            type: GrantScope.granular,
            createdAt: '2026-08-07T10:00:00Z',
            entryId: 'e-1',
            methods: 'get',
            encryptedReason: {
              ...encryptedReason,
              'descriptor': {
                ...reason.descriptor,
                'scope': {
                  ...reason.descriptor['scope'] as Map<String, dynamic>,
                  'grantOrRequestId': 'g-$i',
                  'vaultId': scenario == 'failed-vault' && i == 7
                      ? 'v-2'
                      : 'v-1',
                  if (scenario == 'forged-reason' && i == 0)
                    'entryId': 'forged-entry',
                },
              },
            },
          ),
        );
        final vaults = _Vaults();
        final keys = _Keys();
        final discovery = _Discovery();
        final reasonCrypto = _ReasonCrypto();
        final remote = _Remote();
        final index = _Index();
        final session = VaultSessionStore()..setMemberPrivateKey(Uint8List(32));
        addTearDown(session.clear);
        final temporaryBuffers = <Uint8List>[];
        final decryptGate = Completer<void>();
        Uint8List fresh(Uint8List value) {
          final copy = Uint8List.fromList(value);
          temporaryBuffers.add(copy);
          return copy;
        }

        final vaultKey = Uint8List.fromList(List<int>.filled(32, 7));
        final reasonKey = Uint8List.fromList(List<int>.filled(32, 8));
        final plaintext = Uint8List.fromList(
          utf8.encode('{"reason":"Deploy release"}'),
        );
        final signingKey = Uint8List.fromList(List<int>.filled(32, 9));

        when(() => vaults.getEncryptedVault(any())).thenAnswer((call) async {
          if (scenario == 'timed-reads') {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (scenario == 'failed-vault' &&
              call.positionalArguments.single == 'v-1') {
            throw StateError('Synthetic unavailable context');
          }
          return <String, dynamic>{
            'organizationId': 'org-1',
            'memberVaultKey': <String, dynamic>{'wrappedVaultKey': const {}},
            'vaultPrivateKeys': <Map<String, dynamic>>[
              {
                'descriptor': {
                  'purpose': 'vaultAgentMessagePrivateKey',
                  'keyVersion': 1,
                },
              },
            ],
          };
        });
        when(
          () => keys.openMemberVaultKey(any(), any()),
        ).thenAnswer((_) async => fresh(vaultKey));
        when(
          () => keys.openCanonicalAgentMessagePrivateKey(
            any(),
            any(),
            expectedKeyVersion: 1,
          ),
        ).thenAnswer((_) async => fresh(messagePrivateKey));
        when(() => discovery.list(any())).thenAnswer((_) async {
          if (scenario == 'timed-reads') {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          return [
            AgentDiscoveryProvisioning(
              agentId: 'a-1',
              recipientKeyVersion: 1,
              status: 'current',
              x25519PublicKey: base64Encode(List<int>.filled(32, 1)),
              ed25519PublicKey: base64Encode(signingKey),
            ),
          ];
        });
        when(
          () => reasonCrypto.verifyAndOpenKey(
            reason: any(named: 'reason'),
            signingPublicKey: any(named: 'signingPublicKey'),
            recipientPrivateKey: any(named: 'recipientPrivateKey'),
          ),
        ).thenAnswer((_) async {
          if (scenario == 'lock-during-decrypt') await decryptGate.future;
          return fresh(reasonKey);
        });
        when(
          () => reasonCrypto.decrypt(
            reason: any(named: 'reason'),
            reasonKey: any(named: 'reasonKey'),
          ),
        ).thenAnswer((_) async => fresh(plaintext));

        final delayedGrant = Completer<GrantModel>();
        when(() => remote.getGrant(any(), any())).thenAnswer((call) async {
          final id = call.positionalArguments[1];
          if (id == 'g-0') {
            if (scenario == 'slow-grant') return delayedGrant.future;
            if (scenario == 'unreadable-grant') {
              throw StateError('Synthetic unavailable grant');
            }
          }
          return grants.firstWhere((grant) => grant.id == id);
        });
        when(() => index.waitForCurrent(any())).thenAnswer((_) async {});
        when(() => index.entries(any())).thenReturn([]);
        final repository = GrantsRepositoryImpl(
          remote,
          vaultSessionStore: session,
          reasonResolver: LocalGrantReasonResolver(
            vaults: vaults,
            keys: keys,
            discovery: discovery,
            reasonCrypto: reasonCrypto,
            messageKeyFingerprint: (_) async => fingerprint,
          ),
        );
        final published = <String, InboxNotification>{};
        Future<List<InboxNotification>> resolve() =>
            NotificationPresentationResolver(
              index: index,
              grants: repository,
            ).resolve(
              onResolved: (item) => published[item.id] = item,
              items: [
                for (final grant in grants)
                  InboxNotification(
                    id: grant.id,
                    type: 'grant_approved',
                    category: NotificationCategory.update,
                    titleKey: '',
                    actionState: NotificationActionState.none,
                    occurredAt: DateTime(2026),
                    metadata: {
                      'vaultId': grant.vaultId,
                      'grantId': grant.id,
                      'agentId': 'a-1',
                    },
                  ),
              ],
              unlocked: true,
              activeAccountId: 'account',
              activeOrganizationId: 'org-1',
              activeVaults: [
                for (final vaultId in ['v-1', 'v-2'])
                  VaultEntity(
                    id: vaultId,
                    name: 'Vault',
                    grantMode: GrantMode.granular,
                    createdAt: DateTime(2026),
                    updatedAt: DateTime(2026),
                    entryCount: 1,
                    activeGrantCount: 8,
                    memberCount: 1,
                  ),
              ],
            );
        List<InboxNotification>? timedResult;
        if (scenario == 'timed-reads') {
          fakeAsync((clock) {
            Duration? completedAt;
            resolve().then((value) {
              timedResult = value;
              completedAt = clock.elapsed;
            });
            clock.elapse(const Duration(seconds: 1));
            expect(completedAt, const Duration(milliseconds: 200));
          });
        }
        final completed = timedResult;
        final resolving = completed == null
            ? resolve()
            : Future.value(completed);
        if (scenario == 'slow-grant') {
          await Future<void>.delayed(Duration.zero);
          expect(
            published.values.where((item) => item.metadata['reason'] != null),
            hasLength(7),
          );
          delayedGrant.complete(grants.first);
        }
        if (scenario == 'lock-during-decrypt') {
          await Future<void>.delayed(Duration.zero);
          session.clear();
          decryptGate.complete();
        }
        final overlapping = scenario == 'overlapping-resolutions'
            ? resolve()
            : null;
        final result = await resolving;
        final rejected =
            scenario == 'unreadable-grant' || scenario == 'forged-reason';
        final locked = scenario == 'lock-during-decrypt';
        final failedVault = scenario == 'failed-vault';
        final opens = failedVault
            ? 1
            : locked
            ? 4
            : rejected
            ? 7
            : 8;
        expect(
          result.map((item) => item.metadata['reason']),
          failedVault
              ? [...List.filled(7, null), 'Deploy release']
              : locked
              ? List.filled(8, null)
              : [
                  if (rejected) null else 'Deploy release',
                  ...List.filled(7, 'Deploy release'),
                ],
        );
        var passes = 1;
        if (scenario == 'fresh-resolution' || overlapping != null) {
          final again = await (overlapping ?? resolve());
          expect(
            again.map((item) => item.metadata['reason']),
            List.filled(8, 'Deploy release'),
          );
          passes++;
        }
        expect(temporaryBuffers, hasLength(opens * 4 * passes));
        expect(
          temporaryBuffers.every((buffer) => buffer.every((byte) => byte == 0)),
          true,
        );
        verify(
          () => keys.openMemberVaultKey(any(), any()),
        ).called(opens * passes);
        verify(
          () => remote.getGrant(any(), any()),
        ).called((locked ? 4 : 8) * passes);
        verify(
          () => vaults.getEncryptedVault(any()),
        ).called(failedVault ? 2 : passes);
        verify(() => discovery.list(any())).called(passes);
      },
    );
  }
}
