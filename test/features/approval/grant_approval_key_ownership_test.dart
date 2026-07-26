import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/domain/entities/encrypted_reason.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_approval_review_service.dart';
import 'package:mobile_palladin/features/approval/domain/exceptions/approval_exceptions.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/grant_approval_cubit.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';

class _Repository extends Mock implements ApprovalRepository {}

class _Reviewer extends Mock implements GrantApprovalReviewer {}

void main() {
  test(
    'approve borrows a copy, wipes it, and leaves the owner key intact',
    () async {
      final repository = _Repository();
      Uint8List? borrowed;
      final grant = PendingGrant(
        grantId: 'grant',
        vaultId: 'vault',
        agentId: 'agent',
        entryId: 'entry',
        agentPublicKey: 'public',
        encryptedReason: const EncryptedReason(
          organizationId: 'org',
          vaultId: 'vault',
          entryId: 'entry',
          grantRequestId: 'grant',
          agentId: 'agent',
          requestRevision: '1',
          header: {},
          reasonKeyVersion: 1,
          agentMessageKeyVersion: 1,
          recipientAgentMessageKeyFingerprint: 'fingerprint',
          requestedMethods: 1,
          ciphertext: 'ciphertext',
          agentMessageWrappedReasonDek: 'wrapped',
          agentSignature: 'signature',
        ),
        createdAt: DateTime.utc(2026),
      );
      final owner = Uint8List.fromList([1, 2, 3, 4]);
      registerFallbackValue(Uint8List(0));
      when(
        () => repository.approveGrant(
          grant: grant,
          privateKey: any(named: 'privateKey'),
          limit: const GrantLifetime(),
          methods: const [GrantMethod.get],
          fieldIds: const ['value'],
          reviewedEntryRevision: '1',
        ),
      ).thenAnswer((invocation) async {
        borrowed = invocation.namedArguments[#privateKey] as Uint8List;
      });
      final cubit = GrantApprovalCubit(repository: repository, grant: grant);

      await cubit.approve(
        privateKey: owner,
        limit: const GrantLifetime(),
        methods: const [GrantMethod.get],
        fieldIds: const ['value'],
        reviewedEntryRevision: '1',
      );

      expect(owner, [1, 2, 3, 4]);
      expect(borrowed, isNot(same(owner)));
      expect(borrowed, everyElement(0));
      await cubit.close();
    },
  );

  test('409 wipes decrypted review and requires a fresh review', () async {
    final repository = _Repository();
    final reviewer = _Reviewer();
    final grant = _grant();
    final review = GrantApprovalReview(
      reason: 'temporary deployment',
      entryLabel: 'Production',
      entryRevision: '7',
      agentName: 'Deploy Agent',
      fields: [
        const GrantableApprovalField(
          id: 'value',
          label: 'Value',
          access: AgentFieldAccess.onGrantValue,
        ),
      ],
    );
    registerFallbackValue(Uint8List(0));
    when(
      () => reviewer.open(
        grant: grant,
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => review);
    when(
      () => repository.approveGrant(
        grant: grant,
        privateKey: any(named: 'privateKey'),
        limit: const GrantLifetime(),
        methods: const [GrantMethod.get],
        fieldIds: const ['value'],
        reviewedEntryRevision: '7',
      ),
    ).thenThrow(const ApprovalException(ApprovalErrorKind.conflict));
    final cubit = GrantApprovalCubit(
      repository: repository,
      reviewService: reviewer,
      grant: grant,
    );
    final key = Uint8List.fromList([1, 2, 3, 4]);

    await cubit.loadReview(key);
    expect(cubit.state.review?.reason, 'temporary deployment');
    await cubit.approve(
      privateKey: key,
      limit: const GrantLifetime(),
      methods: const [GrantMethod.get],
      fieldIds: const ['value'],
      reviewedEntryRevision: '7',
    );

    expect(cubit.state.error, ApprovalErrorKind.conflict);
    expect(cubit.state.review, isNull);
    expect(review.reason, isEmpty);
    expect(review.fields, isEmpty);
    expect(key, [1, 2, 3, 4]);
    await cubit.close();
  });
}

PendingGrant _grant() => PendingGrant(
  grantId: 'grant',
  vaultId: 'vault',
  agentId: 'agent',
  entryId: 'entry',
  agentPublicKey: 'public',
  encryptedReason: const EncryptedReason(
    organizationId: 'org',
    vaultId: 'vault',
    entryId: 'entry',
    grantRequestId: 'grant',
    agentId: 'agent',
    requestRevision: '1',
    header: {},
    reasonKeyVersion: 1,
    agentMessageKeyVersion: 1,
    recipientAgentMessageKeyFingerprint: 'fingerprint',
    requestedMethods: 1,
    ciphertext: 'ciphertext',
    agentMessageWrappedReasonDek: 'wrapped',
    agentSignature: 'signature',
  ),
  createdAt: DateTime.utc(2026),
);
