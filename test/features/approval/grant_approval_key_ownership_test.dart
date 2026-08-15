import 'dart:typed_data';
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/domain/entities/encrypted_reason.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_approval_review_service.dart';
import 'package:mobile_palladin/features/approval/domain/exceptions/approval_exceptions.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/grant_approval_cubit.dart';
import 'package:mobile_palladin/features/approval/presentation/widgets/approve_grant_sheet.dart';
import 'package:mobile_palladin/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

class _Repository extends Mock implements ApprovalRepository {}

class _Reviewer extends Mock implements GrantApprovalReviewer {}

class _AuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

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
        encryptedReason: _encryptedReason(),
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

  test(
    'lifecycle cleanup discards and wipes a late decrypted review',
    () async {
      final repository = _Repository();
      final reviewer = _Reviewer();
      final grant = _grant();
      final pending = Completer<GrantApprovalReview>();
      final review = GrantApprovalReview(
        reason: 'late plaintext',
        entryLabel: 'Production',
        entryRevision: '7',
        agentName: 'Agent',
        fields: const [],
      );
      registerFallbackValue(Uint8List(0));
      when(
        () => reviewer.open(
          grant: grant,
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer((_) => pending.future);
      final cubit = GrantApprovalCubit(
        repository: repository,
        reviewService: reviewer,
        grant: grant,
      );

      final load = cubit.loadReview(Uint8List(32));
      cubit.clearReview();
      pending.complete(review);
      await load;

      expect(cubit.state.status, GrantApprovalStatus.idle);
      expect(cubit.state.review, isNull);
      expect(review.reason, isEmpty);
      await cubit.close();
    },
  );

  testWidgets('resume re-opens the wiped review and enables approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _Repository();
    final reviewer = _Reviewer();
    final grant = _grant();
    var openCount = 0;
    when(
      () => reviewer.open(
        grant: grant,
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async {
      openCount++;
      return GrantApprovalReview(
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
    });
    final cubit = GrantApprovalCubit(
      repository: repository,
      reviewService: reviewer,
      grant: grant,
    );
    final auth = _AuthBloc();
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: AuthAuthenticated(
        userId: 'user',
        isOnboarded: true,
        isVaultLocked: false,
        privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
      ),
    );
    addTearDown(cubit.close);
    addTearDown(auth.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<GrantApprovalCubit>.value(value: cubit),
          ],
          child: Scaffold(body: ApproveGrantSheet(grant: grant)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openCount, 1);
    expect(cubit.state.review, isNotNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(cubit.state.review, isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(openCount, 2);
    expect(cubit.state.review, isNotNull);
    final approve = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(approve.onPressed, isNotNull);
  });
}

PendingGrant _grant() => PendingGrant(
  grantId: 'grant',
  vaultId: 'vault',
  agentId: 'agent',
  entryId: 'entry',
  agentPublicKey: 'public',
  encryptedReason: _encryptedReason(),
  createdAt: DateTime.utc(2026),
);

EncryptedReason _encryptedReason() => EncryptedReason(
  descriptor: {
    'scope': {
      'organizationId': 'org',
      'vaultId': 'vault',
      'entryId': 'entry',
      'grantOrRequestId': 'grant',
      'agentId': 'agent',
    },
    'resourceRevision': '1',
    'keyVersion': 1,
    'memberKeyGeneration': 1,
    'binding': {
      'recipientKeyVersion': 1,
      'recipientKeyFingerprint': 'fingerprint',
      'requestedMethods': 1,
    },
  },
  encodedSuitePayload: 'payload',
  wrappedReasonDek: const {},
  agentSignature: 'signature',
);
