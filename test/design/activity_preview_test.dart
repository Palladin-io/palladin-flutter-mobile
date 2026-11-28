import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';
import 'package:mobile_palladin/core/widgets/card_action_footer.dart';
import 'package:mobile_palladin/features/notifications/presentation/widgets/notification_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/agents/domain/entities/agent.dart';
import 'package:mobile_palladin/features/agents/presentation/bloc/agents_cubit.dart';
import 'package:mobile_palladin/features/approval/presentation/cubit/grant_approval_cubit.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/presentation/cubit/org_grants_cubit.dart';
import 'package:mobile_palladin/features/notifications/presentation/cubit/notification_center_cubit.dart';
import 'package:mobile_palladin/features/audit/presentation/cubit/audit_log_cubit.dart';
import '../../design/mobile/activity_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Inbox accept uses shared approval action and preserves callback',
    (tester) async {
      var accepted = false;
      final item = ActivityPreviewStore().notifications.firstWhere(
        (n) => n.type == 'agent_pending',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NotificationCard(
              item: item,
              onTap: () {},
              primaryLabel: 'Accept',
              onPrimary: () => accepted = true,
            ),
          ),
        ),
      );
      expect(find.byType(CardActionFooter), findsOneWidget);
      await tester.tap(find.text('Accept'));
      expect(accepted, true);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'production approval cubit updates grants and collapses pending inbox action',
    () async {
      final store = ActivityPreviewStore();
      final grant = store.pending.first;
      final cubit = GrantApprovalCubit(
        repository: store,
        reviewService: PreviewApprovalReviewer(),
        grant: grant,
      );
      await cubit.loadReview(Uint8List(32));
      expect(cubit.state.status, GrantApprovalStatus.ready);
      await cubit.approve(
        privateKey: Uint8List(32),
        limit: const GrantUseLimit(3),
        methods: [GrantMethod.inject],
        fieldIds: cubit.state.review!.fields.map((f) => f.id).toList(),
        reviewedEntryRevision: '1',
      );
      expect(cubit.state.status, GrantApprovalStatus.done);
      expect(store.pending.any((g) => g.grantId == grant.grantId), false);
      final approved = await store.getGrant(grant.vaultId, grant.grantId);
      expect(approved.status, GrantStatus.active);
      expect(approved.queryLimit, 3);
      expect(
        store.notifications
            .where(
              (n) => n.subjectId == grant.grantId && n.type == 'grant_pending',
            )
            .single
            .isCollapsedPending,
        true,
      );
      await cubit.close();
    },
  );
  test('deny, revoke and agent lifecycle mutate shared preview data', () async {
    final store = ActivityPreviewStore();
    final request = store.pending.last;
    final approval = GrantApprovalCubit(repository: store, grant: request);
    await approval.deny();
    expect(
      (await store.getGrant(request.vaultId, request.grantId)).status,
      GrantStatus.denied,
    );
    final grants = OrgGrantsCubit(repository: store);
    await grants.load();
    await grants.revokeGrant('vault-work', 'grant-active');
    expect(
      (await store.getGrant('vault-work', 'grant-active')).status,
      GrantStatus.revoked,
    );
    final agents = AgentsCubit(repository: store);
    await agents.load();
    await agents.updateAgent(
      'agent-claude',
      name: 'Build assistant',
      description: 'Local preview edit',
    );
    expect((await store.getAgent('agent-claude')).name, 'Build assistant');
    await agents.deactivateAgent('agent-claude');
    expect(
      (await store.getAgent('agent-claude')).status,
      AgentStatus.deactivated,
    );
    await agents.reactivateAgent('agent-claude');
    expect((await store.getAgent('agent-claude')).status, AgentStatus.active);
    await approval.close();
    await grants.close();
    await agents.close();
  });
  test(
    'real inbox read actions and audit local filters work offline',
    () async {
      final store = ActivityPreviewStore();
      final inbox = NotificationCenterCubit(repository: store);
      await inbox.load();
      expect(inbox.state.items, isNotEmpty);
      await inbox.markAllRead();
      expect((await store.summary()).unreadCount, 0);
      final audit = AuditLogCubit(
        auditRepository: store,
        presentationResolver: PreviewAuditNames(),
        scope: AuditLogScope.org,
        entryNameRefreshDelay: Duration.zero,
      );
      await audit.load();
      expect(audit.state.filtered, isNotEmpty);
      audit.search('GitHub');
      expect(
        audit.state.filtered.map((e) => e.id).toSet(),
        store.logs
            .where((e) => e.entryId == 'entry-github')
            .map((e) => e.id)
            .toSet(),
      );
      expect(
        audit.state.filtered.every((e) => e.entryId == 'entry-github'),
        true,
      );
      await inbox.close();
      await audit.close();
    },
  );
}
