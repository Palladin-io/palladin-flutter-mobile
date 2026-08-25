import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/theme/app_colors.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/grants/presentation/widgets/org_grant_card.dart';
import 'package:mobile_palladin/l10n/generated/app_localizations.dart';

void main() {
  Grant grant({
    GrantStatus status = GrantStatus.expired,
    bool canRevoke = false,
    bool canGrantAgain = false,
    List<String> activeCoveringGrantIds = const [],
  }) {
    return Grant(
      id: 'grant-history',
      vaultId: 'vault',
      agentId: 'agent',
      agentName: 'Deploy Agent',
      status: status,
      scope: GrantScope.granular,
      entryId: 'entry',
      entryLabel: 'Deploy token',
      createdAt: DateTime(2026, 8, 1),
      canRevoke: canRevoke,
      canGrantAgain: canGrantAgain,
      activeCoveringGrantIds: activeCoveringGrantIds,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    Grant grant, {
    VoidCallback? onRevoke,
    VoidCallback? onRegrant,
    VoidCallback? onShowActiveGrant,
    VoidCallback? onViewContext,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrgGrantCard(
              grant: grant,
              onRevoke: onRevoke ?? () {},
              onRegrant: onRegrant ?? () {},
              onReviewPending: () {},
              onShowActiveGrant: onShowActiveGrant ?? () {},
              onViewContext: onViewContext ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('active grant footer offers revoke', (tester) async {
    await pumpCard(tester, grant(status: GrantStatus.active, canRevoke: true));

    expect(find.text('Revoke grant'), findsOneWidget);
  });

  testWidgets('pending grant footer opens the review queue', (tester) async {
    await pumpCard(tester, grant(status: GrantStatus.pending));

    expect(find.text('Review request'), findsOneWidget);
  });

  testWidgets('terminal grant footer offers grant again', (tester) async {
    await pumpCard(tester, grant(canGrantAgain: true));

    expect(find.text('Grant again'), findsOneWidget);
  });

  testWidgets('terminal grant links to its newer active coverage', (
    tester,
  ) async {
    var opened = false;
    await pumpCard(
      tester,
      grant(activeCoveringGrantIds: const ['active-grant']),
      onShowActiveGrant: () => opened = true,
    );

    expect(find.text('Active in a newer grant'), findsOneWidget);
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Show active grant'),
    );
    expect(
      action.style?.foregroundColor?.resolve(<WidgetState>{}),
      AppColors.brandRed,
    );
    await tester.tap(find.text('Show active grant'));
    expect(opened, isTrue);
  });

  testWidgets('unavailable terminal grant links to its Agent', (tester) async {
    var opened = false;
    await pumpCard(tester, grant(), onViewContext: () => opened = true);

    expect(find.text('Grant again unavailable'), findsOneWidget);
    await tester.tap(find.text('View agent'));
    expect(opened, isTrue);
  });
}
